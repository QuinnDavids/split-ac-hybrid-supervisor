function [N_occ, occ] = occupancy_profile(p)
%OCCUPANCY_PROFILE  Multi-day stochastic occupancy for a Port Harcourt dwelling.
%   Generates p.days days of occupancy (loops over 1:p.days), so it already
%   scales automatically to any study length set in sim_params.m.
%   [N_occ, occ] = OCCUPANCY_PROFILE(p)
%
%   Outputs
%     occ   : logical column vector, length p.N, true when room is occupied
%     N_occ : integer column vector, length p.N, occupant count
%             (0 when empty, p.N_occ_max when occupied)
%
%   Reproducibility
%     Seeded by p.seed so the SAME realised array is reused for both seasons
%     and all three control strategies (identical inputs for a fair comparison).
%
%   Model (§3.6.4)
%     Day 1 = Monday. Day-type schedule:
%       Weekday (Mon-Fri): one absence per day (work/school).
%                          depart ~ N(6.0, 0.5h), arrive ~ N(18.0, 0.5h),
%                          clipped to defensible bounds. Average ~12 h home.
%       Weekend (Sat-Sun): one outing per day (errands/social).
%                          out_start ~ N(9.0, 1h), out_duration ~ N(8h, 1h),
%                          clipped. Average ~16 h home.
%     Within occupied periods, N_occ = p.N_occ_max (constant household size).

    rng(p.seed);

    steps_per_hour = 3600 / p.dt;
    steps_per_day  = 24 * steps_per_hour;

    occ = false(p.N, 1);
    hour_axis = (0:steps_per_day-1).' / steps_per_hour;     % 0 .. 24-dt/3600

    for day = 1:p.days
        day_offset  = (day-1) * steps_per_day;
        weekday_idx = mod(day-1, 7) + 1;                    % 1=Mon ... 7=Sun
        is_weekend  = weekday_idx >= 6;

        if ~is_weekend
            % Weekday: away during work hours, target ~12 h home
            depart_h = 6.0 + 0.5*randn();
            depart_h = max(5.0, min(7.5, depart_h));
            arrive_h = 18.0 + 0.5*randn();
            arrive_h = max(16.5, min(20.0, arrive_h));
            day_occ  = (hour_axis < depart_h) | (hour_axis >= arrive_h);
        else
            % Weekend: one outing midday, target ~16 h home
            out_dur   = 8 + 1*randn();
            out_dur   = max(5, min(10, out_dur));
            out_start = 9 + 1*randn();
            out_start = max(7, min(11, out_start));
            out_end   = out_start + out_dur;
            day_occ   = (hour_axis < out_start) | (hour_axis >= out_end);
        end

        occ(day_offset + (1:steps_per_day)) = day_occ;
    end

    N_occ = double(occ) * p.N_occ_max;
end
