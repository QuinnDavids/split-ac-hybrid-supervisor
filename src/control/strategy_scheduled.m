function log = strategy_scheduled(T_out, N_occ, p)
%STRATEGY_SCHEDULED  Strategy 2 -- fixed-schedule controller.
%   log = STRATEGY_SCHEDULED(T_out, N_occ, p)
%
%   Behaviour (per §3.6.3)
%     - Setpoint = p.sched_setpoint (22 degC) ONLY during a fixed schedule:
%         weekday  : 06:00-08:00  AND  18:00-23:00
%         weekend  : 07:00-23:00
%     - OFF (sentinel T_set above any T_in) otherwise.
%     - NO adaptation. The schedule is fixed while the realised occupancy
%       from occupancy_profile.m is stochastic, so the two diverge -- the
%       controller cools empty rooms and misses unscheduled presence.
%       That mismatch IS the finding for this strategy.
%
%   Output  log struct (length-N column vectors):
%     T_in, T_set, P_elec, Q_cool, is_on, T_out, N_occ

    T_in       = zeros(p.N, 1);   T_in(1) = p.T_avg;
    T_set_log  = zeros(p.N, 1);
    P_elec_log = zeros(p.N, 1);
    Q_cool_log = zeros(p.N, 1);
    is_on_log  = false(p.N, 1);
    f_mod_log  = zeros(p.N, 1);

    hem.is_on          = false;
    hem.t_since_change = p.dt_min;

    t_s     = (0:p.N-1).' * p.dt;
    t_hour  = mod(t_s/3600, 24);
    day_idx = floor(t_s / 86400) + 1;           % 1..p.days
    weekday = mod(day_idx - 1, 7) + 1;          % 1=Mon ... 7=Sun

    for k = 1:p.N-1
        h     = t_hour(k);
        wknd  = weekday(k) >= 6;

        if wknd
            scheduled = (h >= 7  && h < 23);
        else
            scheduled = (h >= 0  && h < 8) || (h >= 18 && h < 23);
        end

        if scheduled
            ac_on = true;
            T_set = p.sched_setpoint;           % 22 degC
        else
            ac_on = false;                      % AC physically OFF
            T_set = p.sched_setpoint;           % value irrelevant when off
        end

        [Q_cool, P_elec, hem, info] = hem_step(T_in(k), T_out(k), T_set, ac_on, hem, p);
        [T_in(k+1), ~]              = btm_step(T_in(k), T_out(k), N_occ(k), Q_cool, t_hour(k), p);

        T_set_log(k)  = T_set;
        P_elec_log(k) = P_elec;
        Q_cool_log(k) = Q_cool;
        is_on_log(k)  = hem.is_on;
        f_mod_log(k)  = info.f_mod;
    end

    T_set_log(p.N)  = T_set;
    P_elec_log(p.N) = P_elec;
    Q_cool_log(p.N) = Q_cool;
    is_on_log(p.N)  = hem.is_on;
    f_mod_log(p.N)  = info.f_mod;

    log.name   = 'scheduled';
    log.T_in   = T_in;
    log.T_set  = T_set_log;
    log.P_elec = P_elec_log;
    log.Q_cool = Q_cool_log;
    log.is_on  = is_on_log;
    log.f_mod  = f_mod_log;
    log.T_out  = T_out;
    log.N_occ  = N_occ;
end
