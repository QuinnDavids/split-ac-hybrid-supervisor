%RUN_VALIDATION_OKIGWE_RAIN  Tier-1 BTM validation, rainy season, vs Okigwe data.
%
% Purpose
%   Verify the Building Thermal Model STRUCTURE in isolation by simulating
%   the FULL STUDY DURATION (p.days, currently 28 days) of rainy-season
%   weather AT OKIGWE forcing (sim_params_okigwe) with the air-conditioner
%   OFF, and confirming TWO free-run checks against Ogbonnaya (2019)
%   Okigwe field data:
%
%     (1) Peak check   : free-run peak T_in within +/- 1.5 degC of 32 degC.
%     (2) Weekly mean  : the rolling 7-day mean of free-run T_in stays
%                         within the 26.9-28.8 degC band for every
%                         complete week in the simulated period.
%
%   This is a Tier-1 structural validation ONLY -- it does not validate
%   Port Harcourt indoor conditions directly; see run_ph_validation_note.m.
%
% Boundary conditions for the validation
%   - Rainy-season Okigwe parameters   (sim_params_okigwe('rain'))
%   - Q_cool = 0  (no cooling)                                       % passive free-run
%   - N_occ = 0   (empty room: envelope response only)
%   - P_equip overridden to 0 for the validation     (free envelope response)
%   - T_in(0) initialised to T_avg
%
% Pass criterion
%   BOTH (1) and (2) above must pass. If either FAILS, the validation
%   gate requires fixing the BTM (C_th, U_comp, dT_sol -- within
%   physically defensible bounds) BEFORE proceeding to the HEM or any
%   control strategy.

clear; clc; close all;

% ---------------- 1. Load Okigwe rainy-season parameters (Tier 1) --------
p = sim_params_okigwe('rain');

% --- IMPORTANT CHANGE from the previous version of this script ---
% "Free-run" here means Q_cool = 0 (no active cooling), NOT an empty,
% unoccupied building. Ogbonnaya (2019)'s Okigwe field data comes from
% INSTRUMENTED OCCUPIED CASE BUILDINGS (Chapter 3, Section 3.2.1), so the
% comparable model run must include realistic internal gains (occupant
% metabolic heat + equipment load). See run_validation_okigwe_dry.m for
% the full rationale and calibrate_cth_okigwe.m for the supporting
% analytical derivation showing the rainy-season weekly-mean target is
% structurally unreachable under a P_equip=0/N_occ=0 empty-envelope run,
% regardless of C_th.
[N_occ, ~] = occupancy_profile(p);

target_peak   = 32.0;          % degC  Ogbonnaya (2019), Okigwe rainy-season peak
tol_peak      = 1.5;           % degC  acceptance tolerance, peak check

weekmean_lo   = 26.9;          % degC  Okigwe weekly-mean band, lower   O2019
weekmean_hi   = 28.8;          % degC  Okigwe weekly-mean band, upper   O2019

% ---------------- 2. Pre-compute weather ----------------------------------
T_out = weather_profile(p);    % column, length p.N

% ---------------- 3. Free-run simulation -----------------------------------
T_in        = zeros(p.N, 1);
T_in(1)     = p.T_avg;         % init at daily mean
Q_env_log   = zeros(p.N, 1);
Q_sol_log   = zeros(p.N, 1);

t_s    = (0:p.N-1).' * p.dt;
t_hour = mod(t_s/3600, 24);

for k = 1:p.N-1
    [T_in(k+1), Q] = btm_step( T_in(k), T_out(k), N_occ(k), 0, t_hour(k), p );
    Q_env_log(k) = Q.env;
    Q_sol_log(k) = Q.sol;
end

% ---------------- 4a. Peak check --------------------------------------------
peak_T   = max(T_in);
peak_idx = find(T_in == peak_T, 1, 'first');
peak_day = floor((peak_idx-1) * p.dt / 86400) + 1;
peak_hr  = mod((peak_idx-1) * p.dt / 3600, 24);

err_peak  = peak_T - target_peak;
pass_peak = abs(err_peak) <= tol_peak;

% ---------------- 4b. Weekly rolling-mean check -----------------------------
% Compute the mean T_in over each COMPLETE 7-day block of the simulated
% period (non-overlapping weeks: days 1-7, 8-14, 15-21, 22-28, ...).
% This is a new check type not present in the hot-dry validation script.
steps_per_day  = 24*3600 / p.dt;
steps_per_week = 7 * steps_per_day;
n_weeks        = floor(p.N / steps_per_week);

week_means = zeros(n_weeks, 1);
for w = 1:n_weeks
    idx = (w-1)*steps_per_week + (1:steps_per_week);
    week_means(w) = mean(T_in(idx));
end

pass_week_each = (week_means >= weekmean_lo) & (week_means <= weekmean_hi);
pass_weekmean  = n_weeks > 0 && all(pass_week_each);

% ---------------- 4c. Overall verdict ---------------------------------------
pass = pass_peak && pass_weekmean;

fprintf('\n=========== BTM VALIDATION (Tier 1, Okigwe, rainy season) ===========\n');
fprintf(' Season              : rainy, OKIGWE forcing\n');
fprintf(' Duration            : %d days (%d steps @ %d s), %d complete weeks\n', ...
    p.days, p.N, p.dt, n_weeks);
fprintf(' C_th                : %.0f J/K  (calibrated, Tier-1)\n', p.C_th);
fprintf(' U_comp * A_env      : %.1f W/K\n', p.U_comp * p.A_env);
fprintf(' Solar factor        : %.2f    Latent load applied: %d\n', p.solar_factor, p.use_latent);
fprintf(' -----------------------------------------------------------------------\n');
fprintf(' (1) PEAK CHECK\n');
fprintf('     Peak T_in           : %.2f degC   (day %d, %.1f h)\n', peak_T, peak_day, peak_hr);
fprintf('     Target              : %.2f +/- %.2f degC\n', target_peak, tol_peak);
fprintf('     Deviation           : %+.2f degC\n', err_peak);
fprintf('     Result              : %s\n', ternary(pass_peak,'PASS','FAIL'));
fprintf(' -----------------------------------------------------------------------\n');
fprintf(' (2) WEEKLY-MEAN CHECK  (band [%.1f, %.1f] degC)\n', weekmean_lo, weekmean_hi);
for w = 1:n_weeks
    fprintf('     Week %d (days %2d-%2d) : mean T_in = %.2f degC   [%s]\n', ...
        w, (w-1)*7+1, w*7, week_means(w), ternary(pass_week_each(w),'PASS','FAIL'));
end
fprintf('     Result              : %s\n', ternary(pass_weekmean,'PASS','FAIL'));
fprintf(' -----------------------------------------------------------------------\n');
if pass
    fprintf(' VERDICT             : PASS  (both checks within tolerance)\n');
else
    fprintf(' VERDICT             : FAIL  (validation gate -- fix BTM before proceeding)\n');
end
fprintf('=========================================================================\n\n');

% ---------------- 5. Diagnostic plot ----------------------------------------
t_h = t_s / 3600;

fig = figure('Name', 'BTM Validation (Tier 1, Okigwe, rainy)', 'Position', [100 100 1000 750]);

subplot(3,1,1);
plot(t_h, T_out, 'b-', 'LineWidth', 1.2); hold on;
plot(t_h, T_in,  'r-', 'LineWidth', 1.2);
yline(target_peak,            'k--', 'Okigwe rainy peak (32.0)');
yline(target_peak + tol_peak, 'k:',  '+1.5 tol');
yline(target_peak - tol_peak, 'k:',  '-1.5 tol');
xlabel('time (h)'); ylabel('Temperature (degC)');
title(sprintf('BTM free-run, Okigwe rainy season -- peak T_{in} = %.2f degC (%s)', ...
        peak_T, ternary(pass_peak,'PASS','FAIL')));
legend({'T_{out}','T_{in}'}, 'Location','best'); grid on;

subplot(3,1,2);
week_centers_h = ((0:n_weeks-1) + 0.5) * 7 * 24;
plot(week_centers_h, week_means, 'mo-', 'LineWidth', 1.5, 'MarkerFaceColor','m'); hold on;
yline(weekmean_lo, 'k--', 'band lo (26.9)');
yline(weekmean_hi, 'k--', 'band hi (28.8)');
xlabel('time (h)'); ylabel('Weekly mean T_{in} (degC)');
title(sprintf('Weekly rolling mean T_{in} -- %s', ternary(pass_weekmean,'PASS','FAIL')));
grid on; xlim([0, p.days*24]);

subplot(3,1,3);
plot(t_h, Q_env_log, 'b-'); hold on;
plot(t_h, Q_sol_log, 'r-');
xlabel('time (h)'); ylabel('Heat flow (W)');
legend({'Q_{env}','Q_{sol}'}, 'Location','best'); grid on;
title('Envelope and solar gains');

% Persist diagnostic figure to results/figures/
if ~exist('results/figures', 'dir')
    mkdir('results/figures');
end
savefig(fig, 'results/figures/btm_validation_okigwe_rain.fig');
exportgraphics(fig, 'results/figures/btm_validation_okigwe_rain.png', 'Resolution', 150);

% ---------------- helper -----------------------------------
function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end
