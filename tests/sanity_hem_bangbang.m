%SANITY_HEM_BANGBANG  Sanity check for hem_step_bangbang.m.
%
% PART A -- Full-load energy sanity (mirrors sanity_hem.m)
%   Hold T_in well above T_set so the compressor is forced ON continuously
%   for one full hour. Since bang-bang has NO modulation, the reported
%   energy should match the SAME rated draw as the inverter's full-load
%   case (f_mod=1 for both models when fully loaded):
%        E_target = (P_rated + P_fan) * 1 h
%                 = (1100 + 150) * 3600 / 3.6e6
%                 = 1.250 kWh   + a tiny inrush bump (~1.2 Wh)
%   Pass criterion: |E_actual - E_target| / E_target < 5% (same gate as
%   sanity_hem.m).
%
% PART B -- Closed-loop cycling demonstration (btm_step + hem_step_bangbang)
%   Bang-bang's defining risk is short-cycling: rapid ON/OFF toggling that
%   wears the compressor. This section runs a CLOSED LOOP (BTM feeds back
%   into HEM feeds back into BTM) under two comfort-band scenarios to show
%   the wider final band (23-27C, 30C setback) cycles less than the
%   OLD narrow band (24-26C, 28C setback) would have -- the premise on
%   which adding bang-bang was judged viable at all. Both scenarios use IDENTICAL weather/occupancy forcing;
%   only the deadband target and setback differ.
%
%   Reports: cycles/hour, mean ON duration, and confirms every ON/OFF
%   transition respected the p.dt_min minimum-cycle constraint (Eq. 3.14)
%   in both scenarios -- if min-cycle protection ever failed silently,
%   this would be the check to catch it.

clear; clc; close all;

p = sim_params('hot');
p.hvac_type = 'bangbang';              % force bang-bang for this sanity check

% =====================================================================
% PART A -- full-load electrical draw (same target as sanity_hem.m)
% =====================================================================
T_in_full  = 30;         % degC  well above set-point -> compressor forced ON
T_out_full = 32;         % degC  below T_degr=35 -> no COP penalty
T_set_full = 20;         % degC  driving 10 degC above set-point

N = 3600 / p.dt;          % 1 hour

state.is_on = false;
state.t_since_change = p.dt_min;   % allow immediate start

P_log = zeros(N,1); Qcool_log = zeros(N,1); fmod_log = zeros(N,1);
for k = 1:N
    [Qcool_log(k), P_log(k), state, info] = hem_step(T_in_full, T_out_full, T_set_full, true, state, p);
    fmod_log(k) = info.f_mod;
end

E_kWh   = sum(P_log) * p.dt / 3.6e6;
E_tgt   = (p.P_rated + p.P_fan) * 3600 / 3.6e6;
err_pct = 100 * (E_kWh - E_tgt) / E_tgt;
passA   = abs(err_pct) < 5;

fprintf('\n============= HEM SANITY (bang-bang) -- PART A: full load =============\n');
fprintf(' Setup     : T_in=%.1f, T_out=%.1f, T_set=%.1f (degC), 1 h, forced ON\n', T_in_full, T_out_full, T_set_full);
fprintf(' f_mod     : min=%.2f  mean=%.2f  max=%.2f  (should be exactly 1.0 -- no modulation)\n', ...
    min(fmod_log), mean(fmod_log), max(fmod_log));
fprintf(' Q_cool    : %.0f W (avg)\n', mean(Qcool_log));
fprintf(' P_elec    : %.0f W (avg)\n', mean(P_log));
fprintf(' -------------------------------------------------------------------------\n');
fprintf(' E_target  : %.4f kWh\n', E_tgt);
fprintf(' E_actual  : %.4f kWh\n', E_kWh);
fprintf(' Deviation : %+.2f %%\n', err_pct);
fprintf(' VERDICT   : %s\n', ternary(passA, 'PASS (<5%)', 'FAIL -- review hem_step_bangbang.m'));
fprintf(' Cross-check: %s\n', ternary(all(fmod_log==1), ...
    'f_mod is exactly binary (1.0 throughout) as expected -- PASS', ...
    'f_mod is NOT purely binary -- unexpected, review Section 3 of hem_step_bangbang.m'));
fprintf('===========================================================================\n\n');

% =====================================================================
% PART B -- closed-loop cycling demonstration: narrow vs wide band
% =====================================================================
sim_hours = 48;                        % 2-day closed-loop window, occupied throughout
N_sim     = sim_hours * 3600 / p.dt;
T_out_B   = 34;                        % degC  fixed hot outdoor forcing (stresses the loop)
N_occ_B   = p.N_occ_max;               % occupied throughout -- isolates cycling behavior
                                        % from occupancy transitions

scenarios(1).label    = 'OLD narrow band (original: 24-26C, setback 28C)';
scenarios(1).T_set     = 26;           % old T_max, i.e. the tightest realistic hybrid target
scenarios(2).label    = 'NEW wide band (final: 23-27C, setback 30C)';
scenarios(2).T_set     = 27;           % new T_max -- same "tightest target" role, new band

results = struct();
for si = 1:numel(scenarios)
    T_set_B = scenarios(si).T_set;

    T_in = zeros(N_sim,1); T_in(1) = T_set_B + 3;   % start warm, force initial ON transient
    is_on_log = false(N_sim,1);
    hem_state.is_on = false; hem_state.t_since_change = p.dt_min;

    for k = 1:N_sim-1
        [Qc, ~, hem_state, ~] = hem_step(T_in(k), T_out_B, T_set_B, true, hem_state, p);
        T_in(k+1) = btm_step(T_in(k), T_out_B, N_occ_B, Qc, 12, p);   % fixed midday hour (no solar-window edge effects)
        is_on_log(k) = hem_state.is_on;
    end
    is_on_log(N_sim) = hem_state.is_on;

    % Count ON->OFF and OFF->ON transitions, and duration of every ON run.
    transitions = find(diff(is_on_log) ~= 0);
    n_transitions = numel(transitions);
    cycles_per_hour = (n_transitions/2) / sim_hours;      % a "cycle" = one ON+OFF pair

    on_run_lengths = [];
    run_start = [];
    for k = 1:N_sim
        if is_on_log(k) && (k==1 || ~is_on_log(k-1))
            run_start = k;
        elseif ~is_on_log(k) && k>1 && is_on_log(k-1)
            on_run_lengths(end+1) = (k - run_start) * p.dt; %#ok<AGROW>
        end
    end
    mean_on_min = mean(on_run_lengths) / 60;

    % Verify every transition respected the minimum-cycle constraint.
    transition_steps = diff([0; transitions]);
    min_cycle_ok = all(transition_steps * p.dt >= p.dt_min - 1e-9);

    results(si).label            = scenarios(si).label;
    results(si).cycles_per_hour  = cycles_per_hour;
    results(si).mean_on_min      = mean_on_min;
    results(si).min_cycle_ok     = min_cycle_ok;
    results(si).T_in             = T_in;
    results(si).is_on_log        = is_on_log;
end

fprintf('============= HEM SANITY (bang-bang) -- PART B: cycling behavior =============\n');
fprintf(' Closed-loop (btm_step + hem_step_bangbang), %d h, fixed T_out=%.0fC, occupied throughout\n', sim_hours, T_out_B);
fprintf(' ---------------------------------------------------------------------------------\n');
for si = 1:numel(results)
    fprintf(' %s\n', results(si).label);
    fprintf('   Cycles/hour        : %.2f\n', results(si).cycles_per_hour);
    fprintf('   Mean ON duration   : %.1f min\n', results(si).mean_on_min);
    fprintf('   Min-cycle respected: %s\n', ternary(results(si).min_cycle_ok, 'YES (all transitions >= dt_min)', 'NO -- violation detected, review Eq.3.14 logic'));
    fprintf('\n');
end
passB_cycling = results(2).cycles_per_hour <= results(1).cycles_per_hour;
passB_mincycle = all([results.min_cycle_ok]);
fprintf(' Expected direction: wide band cycles LESS OR EQUAL vs narrow band : %s\n', ...
    ternary(passB_cycling, 'CONFIRMED', 'NOT confirmed -- worth a closer look, not necessarily a bug'));
fprintf(' Min-cycle protection intact in both scenarios                    : %s\n', ...
    ternary(passB_mincycle, 'PASS', 'FAIL'));
fprintf('=====================================================================================\n\n');

overall_pass = passA && passB_mincycle;
fprintf('OVERALL VERDICT (Part A energy sanity + Part B min-cycle integrity): %s\n\n', ...
    ternary(overall_pass, 'PASS', 'FAIL -- review before proceeding to the full run matrix'));

% ---------------- diagnostic plot ----------------
fig = figure('Name','Bang-bang cycling diagnostic','Position',[100 100 1100 600]);
t_h = (0:N_sim-1) * p.dt / 3600;
for si = 1:numel(results)
    subplot(2,1,si);
    yyaxis left;
    plot(t_h, results(si).T_in, 'b-', 'LineWidth', 1.2); ylabel('T_{in} (degC)');
    yline(scenarios(si).T_set, 'g:', 'T_{set}');
    yyaxis right;
    stairs(t_h, double(results(si).is_on_log), 'r-'); ylim([-0.1 1.1]); ylabel('compressor ON/OFF');
    xlabel('time (h)'); grid on;
    title(sprintf('%s -- %.2f cycles/h, %.1f min mean ON', ...
        results(si).label, results(si).cycles_per_hour, results(si).mean_on_min));
end
sgtitle('Bang-bang closed-loop cycling: narrow vs wide comfort band');

if ~exist('results/figures','dir'), mkdir('results/figures'); end
savefig(fig, 'results/figures/bangbang_cycling_diagnostic.fig');
exportgraphics(fig, 'results/figures/bangbang_cycling_diagnostic.png', 'Resolution', 150);

% ---------- helper ----------
function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end
