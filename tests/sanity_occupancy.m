%SANITY_OCCUPANCY  Sanity check for occupancy_profile.m.
%
% Verifies:
%   (1) Realised weekday hours occupied ~ p.hours_weekday  +/- 10 %
%   (2) Realised weekend hours occupied ~ p.hours_weekend  +/- 10 %
%   (3) Reproducibility: two calls with the same seed give IDENTICAL arrays
%       (needed so every strategy sees identical occupancy).
%
% Also plots the full simulated period (p.days) and the average diurnal
% pattern. Nothing here is hardcoded to a specific number of days -- p.days
% is read from sim_params.m throughout.

clear; clc; close all;

p = sim_params('hot');                  % season choice irrelevant for occupancy

[N_occ, occ] = occupancy_profile(p);

steps_per_hour = 3600 / p.dt;
steps_per_day  = 24 * steps_per_hour;

% ---------------- per-day hours occupied -----------------
hours_per_day = zeros(p.days,1);
dtype = strings(p.days,1);
for d = 1:p.days
    seg = occ((d-1)*steps_per_day + (1:steps_per_day));
    hours_per_day(d) = sum(seg) / steps_per_hour;
    is_wknd = (mod(d-1,7)+1) >= 6;
    dtype(d) = ternary(is_wknd, "weekend", "weekday");
end

mean_wkday = mean(hours_per_day(dtype == "weekday"));
mean_wknd  = mean(hours_per_day(dtype == "weekend"));

tol = 0.10;
pass_wkday = abs(mean_wkday - p.hours_weekday)/p.hours_weekday <= tol;
pass_wknd  = abs(mean_wknd  - p.hours_weekend)/p.hours_weekend <= tol;

% ---------------- reproducibility check -----------------
[N_occ2, occ2] = occupancy_profile(p);
pass_repro = isequal(N_occ, N_occ2) && isequal(occ, occ2);

% ---------------- report --------------------------------
fprintf('\n==================== OCCUPANCY SANITY ====================\n');
fprintf(' Seed                  : %d\n', p.seed);
fprintf(' Days simulated        : %d  (day 1 = Monday)\n', p.days);
fprintf(' --------------------------------------------------------\n');
for d = 1:p.days
    fprintf('  Day %d (%s): %5.2f h occupied\n', d, dtype(d), hours_per_day(d));
end
fprintf(' --------------------------------------------------------\n');
fprintf(' Weekday mean : %.2f h   target %.0f h  [%s]\n', ...
    mean_wkday, p.hours_weekday, ternary(pass_wkday,'PASS','FAIL'));
fprintf(' Weekend mean : %.2f h   target %.0f h  [%s]\n', ...
    mean_wknd,  p.hours_weekend, ternary(pass_wknd, 'PASS','FAIL'));
fprintf(' Reproducible : %s\n', ternary(pass_repro,'PASS','FAIL'));
fprintf('==========================================================\n\n');

% ---------------- plot ----------------------------------
t_h = (0:p.N-1).' * p.dt / 3600;

fig = figure('Name','Occupancy profile','Position',[100 100 1100 600]);

subplot(2,1,1);
stairs(t_h, double(occ), 'b-', 'LineWidth', 1.2);
ylim([-0.1 1.1]); grid on;
xlabel('time (h, day 1 starts Monday 00:00)');
ylabel('occupied (0/1)');
title(sprintf('%d-day realised occupancy  (seed = %d)', p.days, p.seed));
% day separators
for d = 1:p.days-1
    xline(d*24, 'k:');
end

subplot(2,1,2);
% average diurnal pattern by day type
hour_grid = linspace(0, 24, steps_per_day+1);
hour_grid = hour_grid(1:end-1);
diurnal_wkday = zeros(steps_per_day,1);
diurnal_wknd  = zeros(steps_per_day,1);
n_wkday = 0; n_wknd = 0;
for d = 1:p.days
    seg = occ((d-1)*steps_per_day + (1:steps_per_day));
    if (mod(d-1,7)+1) >= 6
        diurnal_wknd  = diurnal_wknd  + double(seg);
        n_wknd = n_wknd + 1;
    else
        diurnal_wkday = diurnal_wkday + double(seg);
        n_wkday = n_wkday + 1;
    end
end
if n_wkday>0, diurnal_wkday = diurnal_wkday / n_wkday; end
if n_wknd >0, diurnal_wknd  = diurnal_wknd  / n_wknd;  end
plot(hour_grid, diurnal_wkday, 'b-', 'LineWidth', 1.5); hold on;
plot(hour_grid, diurnal_wknd,  'r-', 'LineWidth', 1.5); grid on;
xlabel('hour of day'); ylabel('P(occupied)');
legend({'weekday avg','weekend avg'}, 'Location','best');
title('Average diurnal occupancy by day-type');
xlim([0 24]);

if ~exist('results/figures','dir'), mkdir('results/figures'); end
savefig(fig, 'results/figures/occupancy_profile.fig');
exportgraphics(fig, 'results/figures/occupancy_profile.png', 'Resolution', 150);

% ---------- helper ----------
function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end
