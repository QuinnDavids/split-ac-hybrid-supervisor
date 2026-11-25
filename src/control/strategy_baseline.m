function log = strategy_baseline(T_out, N_occ, p)
%STRATEGY_BASELINE  Strategy 1 -- manual ("18 then 22") baseline.
%   log = STRATEGY_BASELINE(T_out, N_occ, p)
%
%   Behaviour (per §3.6.3, with implementation refinements below)
%     - On every occupant arrival: T_set = 18 degC          (overcool habit)
%     - After p.base_raise_min minutes of occupancy: raise to T_set = 22 degC
%     - On the LAST departure of each day, with probability p.base_leaveon_prob,
%       leave the unit running at 22 degC until the next occupied event.
%       Otherwise the AC is switched OFF (T_set sentinel above any T_in).
%   Justification for the leave-on coin: Ogbonnaya (2019) reports many PH
%   households running units 16-24 h/day.
%
%   Output  log struct (length-N column vectors):
%     T_in, T_set, P_elec, Q_cool, is_on, T_out, N_occ

    rng(p.seed + 1);                              % isolate baseline RNG stream

    steps_per_day = 24 * 3600 / p.dt;

    % --- 1. Pre-compute "AC left on overnight" intervals --------------
    %     For each day d, draw a coin. If TRUE, find the LAST departure
    %     event of that day and mark [last_dep .. next_arrival-1] as
    %     "leave-on" (T_set = 22 even while unoccupied).
    occ = N_occ > 0;
    leave_on = false(p.N, 1);

    for d = 1:p.days
        if rand() >= p.base_leaveon_prob
            continue;                              % no leave-on this day
        end
        day_lo = (d-1)*steps_per_day + 1;
        day_hi = min(d*steps_per_day, p.N);

        % find last index in this day where occ goes true -> false
        last_dep = -1;
        for k = day_lo+1 : day_hi
            if occ(k-1) && ~occ(k)
                last_dep = k;
            end
        end
        if last_dep < 0, continue; end             % no departure this day

        % from last_dep, run until the next occupied step (or sim end)
        next_occ_rel = find(occ(last_dep:end), 1, 'first');
        if isempty(next_occ_rel)
            end_idx = p.N;
        else
            end_idx = last_dep + next_occ_rel - 2; % step BEFORE re-occupied
        end
        leave_on(last_dep:end_idx) = true;
    end

    % --- 2. Storage ---------------------------------------------------
    T_in       = zeros(p.N, 1);   T_in(1) = p.T_avg;
    T_set_log  = zeros(p.N, 1);
    P_elec_log = zeros(p.N, 1);
    Q_cool_log = zeros(p.N, 1);
    is_on_log  = false(p.N, 1);
    f_mod_log  = zeros(p.N, 1);

    hem.is_on          = false;
    hem.t_since_change = p.dt_min;                % allow immediate start

    t_s    = (0:p.N-1).' * p.dt;
    t_hour = mod(t_s/3600, 24);

    % --- 3. Initial arrival_step (if occupied at t=0) -----------------
    prev_occ      = false;
    arrival_step  = -1;

    % --- 4. Main loop -------------------------------------------------
    for k = 1:p.N-1
        cur_occ = occ(k);

        % arrival detection
        if cur_occ && ~prev_occ
            arrival_step = k;
        end

        % choose T_set and AC enable
        if cur_occ
            ac_on = true;
            mins_since_arrival = (k - arrival_step) * p.dt / 60;
            if mins_since_arrival < p.base_raise_min
                T_set = p.base_T_initial;          % 18 degC  -- overcool
            else
                T_set = p.base_T_comfort;          % 22 degC
            end
        else
            if leave_on(k)
                ac_on = true;
                T_set = p.base_T_comfort;          % 22 degC, room empty
            else
                ac_on = false;                     % AC physically OFF
                T_set = p.base_T_comfort;          % T_set value irrelevant when off
            end
        end

        % HEM + BTM
        [Q_cool, P_elec, hem, info] = hem_step(T_in(k), T_out(k), T_set, ac_on, hem, p);
        [T_in(k+1), ~]              = btm_step(T_in(k), T_out(k), N_occ(k), Q_cool, t_hour(k), p);

        % log
        T_set_log(k)  = T_set;
        P_elec_log(k) = P_elec;
        Q_cool_log(k) = Q_cool;
        is_on_log(k)  = hem.is_on;
        f_mod_log(k)  = info.f_mod;

        prev_occ = cur_occ;
    end

    % carry final-step logs forward so all arrays are length N
    T_set_log(p.N)  = T_set;
    P_elec_log(p.N) = P_elec;
    Q_cool_log(p.N) = Q_cool;
    is_on_log(p.N)  = hem.is_on;
    f_mod_log(p.N)  = info.f_mod;

    % --- 5. Pack log --------------------------------------------------
    log.name   = 'baseline';
    log.T_in   = T_in;
    log.T_set  = T_set_log;
    log.P_elec = P_elec_log;
    log.Q_cool = Q_cool_log;
    log.is_on  = is_on_log;
    log.f_mod  = f_mod_log;
    log.T_out  = T_out;
    log.N_occ  = N_occ;
    log.leave_on = leave_on;
end
