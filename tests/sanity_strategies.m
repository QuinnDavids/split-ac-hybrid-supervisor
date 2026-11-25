%SANITY_STRATEGIES  Sanity check for all THREE control strategies.
%
% Runs strategy_baseline, strategy_scheduled, strategy_hybrid on the same
% hot-dry weather + seeded occupancy. Verifies:
%   (1) Each produces length-N logs with no NaN / Inf.
%   (2) Energy and runtime numbers are within sane bounds.
%   (3) Compressor duty cycle in (0, 1).
%   (4) Hybrid pre-cool trigger fires at least once.
%
% Plots the first evaluation day (p.learn_days + 1) for visual inspection.
% Driven dynamically by p.learn_days, so it stays correct under any
% learn/eval split (currently day 15 of 28).

clear; clc; close all;

p     = sim_params('hot');
T_out = weather_profile(p);
[N_occ, occ] = occupancy_profile(p);

log_b = strategy_baseline (T_out, N_occ, p);
log_s = strategy_scheduled(T_out, N_occ, p);
log_h = strategy_hybrid   (T_out, N_occ, p);

% ---------------- numeric sanity ----------------
checks = {};
for tag = {'baseline','scheduled','hybrid'}
    name = tag{1};
    switch name
        case 'baseline',  L = log_b;
        case 'scheduled', L = log_s;
        case 'hybrid',    L = log_h;
    end
    checks{end+1} = check([name ' T_in finite'],    all(isfinite(L.T_in)));    %#ok<*SAGROW>
    checks{end+1} = check([name ' P_elec finite'],  all(isfinite(L.P_elec)));
    E_kWh = sum(L.P_elec) * p.dt / 3.6e6;
    duty  = mean(L.is_on);
    % Bounds were originally calibrated as [1, 200] kWh for a 7-day run;
    % scaled here to p.days so the check stays meaningful at 28 days (or any
    % other study length) instead of false-failing on a longer total.
    E_lo = 1   * (p.days / 7);
    E_hi = 200 * (p.days / 7);
    checks{end+1} = check(sprintf('%s energy in [%.0f, %.0f] kWh', name, E_lo, E_hi), ...
        E_kWh > E_lo && E_kWh < E_hi);
    checks{end+1} = check([name ' duty in (0,1)'], duty > 0 && duty < 1);
end
checks{end+1} = check('hybrid triggers > 0', sum(log_h.trigger) > 0);

all_pass = all(cellfun(@(c) c.pass, checks));

% ---------------- summary ----------------
E_b = sum(log_b.P_elec) * p.dt / 3.6e6;
E_s = sum(log_s.P_elec) * p.dt / 3.6e6;
E_h = sum(log_h.P_elec) * p.dt / 3.6e6;

fprintf('\n==================== STRATEGY SANITY (hot-dry, %d days) ====================\n', p.days);
for i = 1:numel(checks)
    fprintf('  [%s] %s\n', tern(checks{i}.pass,'PASS','FAIL'), checks{i}.label);
end
fprintf(' ---------------------------------------------------------------------------\n');
fprintf('  Baseline   : E = %6.2f kWh   duty = %5.2f%%   T_in: [%.1f, %.1f] degC\n', ...
    E_b, 100*mean(log_b.is_on), min(log_b.T_in), max(log_b.T_in));
fprintf('  Scheduled  : E = %6.2f kWh   duty = %5.2f%%   T_in: [%.1f, %.1f] degC\n', ...
    E_s, 100*mean(log_s.is_on), min(log_s.T_in), max(log_s.T_in));
fprintf('  Hybrid     : E = %6.2f kWh   duty = %5.2f%%   T_in: [%.1f, %.1f] degC\n', ...
    E_h, 100*mean(log_h.is_on), min(log_h.T_in), max(log_h.T_in));
fprintf('  Hybrid     : triggers fired = %d   U_est(final) = %.3f W/m^2K\n', ...
    sum(log_h.trigger), log_h.learn_final.U_est);
fprintf('  Hybrid     : T_pref(final)  = %.2f degC\n', log_h.learn_final.T_pref);
fprintf(' ---------------------------------------------------------------------------\n');
fprintf('  Overall    : %s\n', tern(all_pass,'PASS','FAIL'));
fprintf('===========================================================================\n\n');

% ---------------- plot first evaluation day ----------------
% day is derived from p.learn_days so this always lands on the first day
% OUTSIDE the warm-up window, regardless of the learn/eval split in use
% (currently day 15 of 28, previously day 4 of 7).
steps_per_day = 24*3600/p.dt;
day = p.learn_days + 1;
idx = (day-1)*steps_per_day + (1:steps_per_day);
hh  = (0:steps_per_day-1) * p.dt / 3600;

fig = figure('Name', sprintf('Strategies, day %d (hot-dry)', day), 'Position',[60 60 1300 800]);

subplot(3,1,1);
plot(hh, T_out(idx), 'k-', 'LineWidth', 1.0); hold on;
plot(hh, log_b.T_in(idx), 'b-', 'LineWidth', 1.2);
plot(hh, log_s.T_in(idx), 'r-', 'LineWidth', 1.2);
plot(hh, log_h.T_in(idx), 'm-', 'LineWidth', 1.5);
yline(p.T_min, 'g:'); yline(p.T_max, 'g:');
xlabel('hour'); ylabel('T (degC)'); grid on;
legend({'T_{out}','Baseline','Scheduled','Hybrid','comfort band'},'Location','best');
title(sprintf('Day %d (first evaluation day) indoor temperature', day));

subplot(3,1,2);
plot(hh, log_b.T_set(idx), 'b-', 'LineWidth', 1.0); hold on;
plot(hh, log_s.T_set(idx), 'r-', 'LineWidth', 1.0);
plot(hh, log_h.T_set(idx), 'm-', 'LineWidth', 1.5);
plot(hh, 24 + 4*occ(idx),  'k:', 'LineWidth', 1.0);   % occ overlay
ylim([15 33]);   % was [15 32], bumped for new T_setback=30 headroom
xlabel('hour'); ylabel('T_{set} (degC) / occ flag');
grid on;
legend({'Baseline T_{set}','Scheduled T_{set}','Hybrid T_{set}','occupied (top=28)'},'Location','best');
title('Set-point trajectories and realised occupancy');

subplot(3,1,3);
plot(hh, log_b.P_elec(idx), 'b-'); hold on;
plot(hh, log_s.P_elec(idx), 'r-');
plot(hh, log_h.P_elec(idx), 'm-', 'LineWidth', 1.3);
xlabel('hour'); ylabel('P_{elec} (W)'); grid on;
legend({'Baseline','Scheduled','Hybrid'},'Location','best');
title('Electrical power');

if ~exist('results/figures','dir'), mkdir('results/figures'); end
savefig(fig, sprintf('results/figures/strategies_day%d_hot.fig', day));
exportgraphics(fig, sprintf('results/figures/strategies_day%d_hot.png', day), 'Resolution', 150);

% ---------- helpers ----------
function c = check(label, cond)
    c.label = label; c.pass = cond;
end
function s = tern(c,a,b), if c, s=a; else, s=b; end, end
