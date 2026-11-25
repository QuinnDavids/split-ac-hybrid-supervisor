%CALIBRATE_CTH_OKIGWE_REFINE  Tight refinement around the near-miss region.
%
% The first-pass joint sweep (calibrate_cth_okigwe.m, same folder) reported a "closest
% candidate" of C_th = 4.113e6 J/K, solar_factor_rain = 0.625, with total
% violation only 0.023 degC -- close enough to zero that it could be a
% grid-resolution artifact rather than a genuine miss. That script's
% console output only printed sf_grid(1) = 0.425 rows plus any passing
% row, so the actual numbers at sf = 0.625 were never shown. This script
% prints EVERY row in a tight window around the near-miss region so we
% can see exactly what's happening, with much finer resolution on both
% axes.
%
% Search window (centered on the first-pass near-miss):
%   C_th            : 3.6e6 to 4.6e6 J/K   (41 points, linear)
%   solar_factor_rain : 0.55 to 0.625      (16 points, linear -- upper
%                                            portion of the cited
%                                            0.425-0.625 range only,
%                                            since lower values were
%                                            already shown to be worse)

clear; clc; close all;

p_ref      = sim_params_okigwe('hot');
[N_occ, ~] = occupancy_profile(p_ref);

steps_per_day  = 24*3600 / p_ref.dt;
steps_per_week = 7 * steps_per_day;
n_weeks        = floor(p_ref.N / steps_per_week);

hot_lo = 35.0;  hot_hi = 38.0;
rain_peak_lo = 30.5; rain_peak_hi = 33.5;
rain_wm_lo = 26.9; rain_wm_hi = 28.8;

function [peak_T, week_means] = free_run_peak(p, N_occ, steps_per_week, n_weeks)
    T_out = weather_profile(p);
    T_in  = zeros(p.N, 1);
    T_in(1) = p.T_avg;
    t_s    = (0:p.N-1).' * p.dt;
    t_hour = mod(t_s/3600, 24);
    for k = 1:p.N-1
        [T_in(k+1), ~] = btm_step(T_in(k), T_out(k), N_occ(k), 0, t_hour(k), p);
    end
    peak_T = max(T_in);
    week_means = zeros(n_weeks,1);
    for w = 1:n_weeks
        idx = (w-1)*steps_per_week + (1:steps_per_week);
        week_means(w) = mean(T_in(idx));
    end
end

C_grid  = linspace(3.6e6, 4.6e6, 41);
sf_grid = linspace(0.55, 0.625, 16);

nC = numel(C_grid); nS = numel(sf_grid);
best_viol = Inf; best_C = NaN; best_sf = NaN;
pass_list = [];

fprintf('\n=========== TIGHT REFINEMENT SWEEP (every row shown) ===========\n');
fprintf('  %-10s | %-6s | %8s | %9s | %20s | %s\n', ...
    'C_th', 'sf_rn', 'Hot pk', 'Rain pk', 'Rain weekly mean rng', 'PASS?');
fprintf('  %s\n', repmat('-',1,72));

% Hot-dry peak only depends on C_th, so compute it once per C_th value.
hot_by_C = zeros(nC,1);
for i = 1:nC
    p_hot = sim_params_okigwe('hot'); p_hot.C_th = C_grid(i);
    hot_by_C(i) = free_run_peak(p_hot, N_occ, steps_per_week, n_weeks);
end

for i = 1:nC
    hp = hot_by_C(i);
    ph = hp >= hot_lo && hp <= hot_hi;
    for j = 1:nS
        p_rain = sim_params_okigwe('rain');
        p_rain.C_th = C_grid(i);
        p_rain.solar_factor = sf_grid(j);
        [rp, wm] = free_run_peak(p_rain, N_occ, steps_per_week, n_weeks);
        wm_lo = min(wm); wm_hi = max(wm);

        pr = rp >= rain_peak_lo && rp <= rain_peak_hi;
        pw = wm_lo >= rain_wm_lo && wm_hi <= rain_wm_hi;
        all_pass = ph && pr && pw;

        viol = max(0,hot_lo-hp)+max(0,hp-hot_hi) + ...
               max(0,rain_peak_lo-rp)+max(0,rp-rain_peak_hi) + ...
               max(0,rain_wm_lo-wm_lo)+max(0,wm_hi-rain_wm_hi);
        if viol < best_viol
            best_viol = viol; best_C = C_grid(i); best_sf = sf_grid(j);
        end
        if all_pass
            pass_list(end+1,:) = [C_grid(i), sf_grid(j)]; %#ok<AGROW>
        end

        % Print every combination where hot passes (the only region that
        % can possibly also satisfy rain), to keep output readable.
        if ph
            fprintf('  %10.3e | %6.3f | %8.2f | %9.2f | [%6.2f, %6.2f] | %s\n', ...
                C_grid(i), sf_grid(j), hp, rp, wm_lo, wm_hi, ternary(all_pass,'YES','no'));
        end
    end
end

fprintf('\n===================================================================\n');
if ~isempty(pass_list)
    fprintf(' %d combination(s) PASS all three criteria.\n\n', size(pass_list,1));
    mid = pass_list(round(size(pass_list,1)/2), :);
    fprintf(' Suggested calibrated values (middle of passing set):\n');
    fprintf('   p.C_th          = %.0f;   %% J/K\n', mid(1));
    fprintf('   p.solar_factor  = %.4f;  %% -  rainy season only\n\n', mid(2));
else
    fprintf(' Still no exact pass. Best candidate:\n');
    fprintf('   C_th = %.4e J/K,  solar_factor_rain = %.4f,  total violation = %.4f degC\n\n', ...
        best_C, best_sf, best_viol);
    fprintf(' At this resolution that is the genuine floor of what (C_th, solar_factor_rain)\n');
    fprintf(' alone can achieve. Recommend treating this as option (a) from the previous\n');
    fprintf(' message -- report the near-miss explicitly in Chapter 4 -- unless you want\n');
    fprintf(' to open floor_area as a third calibration axis (option b).\n');
end
fprintf('===================================================================\n\n');

function s = ternary(cond, a, b)
    if cond, s = a; else, s = b; end
end