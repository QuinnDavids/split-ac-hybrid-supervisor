%SANITY_HEM  Sanity check for hem_step.m (inverter model).
%
% Test
%   Hold T_in well above T_set so the inverter modulates at f_mod = 1 for
%   one full hour. The reported energy should match the rated draw:
%        E_target = (P_rated + P_fan) * 1 h
%                 = (1100 + 150) * 3600 / 3.6e6
%                 = 1.250 kWh    + a tiny inrush bump (~1.2 Wh)
%
% Pass criterion
%   |E_actual - E_target| / E_target  <  5%   (HVAC model energy gate)

clear; clc; close all;

p = sim_params('hot');

% --- Fixed boundary conditions to force full-load ---
T_in  = 30;         % degC  well above set-point -> f_mod saturates at 1
T_out = 32;         % degC  outdoor; below T_degr=35 -> no COP penalty
T_set = 20;         % degC  driving 10 degC above set-point

% --- 1 hour run at 60-s steps ---
N = 3600 / p.dt;

state.is_on = false;
state.t_since_change = p.dt_min;   % allow immediate start

P_log    = zeros(N,1);
Qcool_log= zeros(N,1);
fmod_log = zeros(N,1);

for k = 1:N
    [Qcool_log(k), P_log(k), state, info] = hem_step(T_in, T_out, T_set, true, state, p);
    fmod_log(k) = info.f_mod;
end

E_kWh  = sum(P_log) * p.dt / 3.6e6;          % Eq. 3.33
E_tgt  = (p.P_rated + p.P_fan) * 3600 / 3.6e6;
err_pct= 100 * (E_kWh - E_tgt) / E_tgt;
pass   = abs(err_pct) < 5;

Qcool_avg = mean(Qcool_log);
COP_eff   = mean(Qcool_log) / mean(P_log);

fprintf('\n==================== HEM SANITY ====================\n');
fprintf(' Setup     : T_in=%.1f, T_out=%.1f, T_set=%.1f (degC), 1 h\n', T_in,T_out,T_set);
fprintf(' f_mod     : min=%.2f  mean=%.2f  max=%.2f\n', min(fmod_log), mean(fmod_log), max(fmod_log));
fprintf(' Q_cool    : %.0f W (avg)\n', Qcool_avg);
fprintf(' P_elec    : %.0f W (avg)\n', mean(P_log));
fprintf(' Effective COP (Q_cool/P_elec, incl. fan): %.2f\n', COP_eff);
fprintf(' ----------------------------------------------------\n');
fprintf(' E_target  : %.4f kWh\n', E_tgt);
fprintf(' E_actual  : %.4f kWh\n', E_kWh);
fprintf(' Deviation : %+.2f %%\n', err_pct);
if pass
    fprintf(' VERDICT   : PASS (<5%%)\n');
else
    fprintf(' VERDICT   : FAIL -- review hem_step.m\n');
end
fprintf('====================================================\n\n');

% --- Modulation curve diagnostic --------------------------------
fig = figure('Name','HEM modulation curve','Position',[100 100 900 400]);
dT_grid = linspace(0, p.dT_max + 2, 100);
f_grid  = max(p.f_mod_min, min(1, dT_grid / p.dT_max));
plot(dT_grid, f_grid, 'b-', 'LineWidth', 1.5); grid on;
xlabel('T_{in} - T_{set}  (degC)'); ylabel('f_{mod}');
title('Inverter modulation curve (Eq. 3.27)');
yline(p.f_mod_min, 'k:', 'f_{mod,min}');
yline(1,           'k:', 'f_{mod,max}');
xline(p.dT_max,    'k:', '\DeltaT_{max}');

if ~exist('results/figures','dir'), mkdir('results/figures'); end
savefig(fig, 'results/figures/hem_modulation_curve.fig');
exportgraphics(fig, 'results/figures/hem_modulation_curve.png', 'Resolution', 150);
