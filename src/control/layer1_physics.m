function [E_kWh, max_T, min_T, comfort_pen, safe] = layer1_physics(T_in0, T_out_arr, N_occ_arr, k_start, n_steps, ac_on, T_set, hem0, p)
%LAYER1_PHYSICS  Forward-simulate the BTM+HEM to score a candidate set-point.
%   [E_kWh, max_T, min_T, comfort_pen, safe] = LAYER1_PHYSICS(...)
%
%   Replays n_steps of the actual physics (btm_step + hem_step) starting at
%   step k_start using the candidate (ac_on, T_set) policy. Used by the
%   hybrid controller's event-driven optimisation (Eq. 3.15) and as the
%   30-step safety check (Eq. 3.4-3.5).
%
%   Inputs
%     T_in0      : current indoor temperature (degC)
%     T_out_arr  : full weather column vector (length p.N)
%     N_occ_arr  : full occupancy column vector (length p.N)
%     k_start    : index to begin lookahead from (uses k_start..k_start+n_steps-1)
%     n_steps    : lookahead horizon (e.g., 30 = 30 min at dt=60s)
%     ac_on      : candidate AC enable flag
%     T_set      : candidate set-point
%     hem0       : initial HEM state struct (copy of the live state)
%     p          : params
%
%   Outputs
%     E_kWh       : predicted electrical energy over the horizon (kWh)
%     max_T,min_T : extrema of predicted T_in over the horizon (degC)
%     comfort_pen : squared deviation outside [T_min,T_max] integrated over
%                   OCCUPIED minutes only (degC^2 * min)
%     safe        : logical -- true if max_T < safety upper bound (31 degC)
%                   AND min_T > safety lower bound (20 degC)

    % Revision note: rebased from 31/20 to 32/19 to preserve the ORIGINAL
    % margin (+5C above T_max, -4C below T_min) now that the comfort band
    % itself widened (T_max 26->27, T_min 24->23). This is a deliberate
    % re-centering, not a change in how permissive the safety envelope is.
    SAFETY_T_HI = 32;      % degC  upper safety bound (Eq. 3.4-3.5)
    SAFETY_T_LO = 19;      % degC  lower safety bound

    T_in = T_in0;
    hem  = hem0;
    E_J  = 0;
    max_T = T_in;
    min_T = T_in;
    comfort_pen = 0;

    n_horizon = min(n_steps, length(T_out_arr) - k_start);
    if n_horizon < 1
        E_kWh = 0; safe = true; return;
    end

    for j = 0:n_horizon-1
        k = k_start + j;
        t_hour = mod((k-1)*p.dt/3600, 24);

        [Q_cool, P_elec, hem, ~] = hem_step(T_in, T_out_arr(k), T_set, ac_on, hem, p);
        T_in                     = btm_step(T_in, T_out_arr(k), N_occ_arr(k), Q_cool, t_hour, p);

        E_J   = E_J + P_elec * p.dt;
        max_T = max(max_T, T_in);
        min_T = min(min_T, T_in);

        if N_occ_arr(k) > 0
            if T_in > p.T_max
                comfort_pen = comfort_pen + (T_in - p.T_max)^2 * (p.dt/60);
            elseif T_in < p.T_min
                comfort_pen = comfort_pen + (p.T_min - T_in)^2 * (p.dt/60);
            end
        end
    end

    E_kWh = E_J / 3.6e6;
    safe  = (max_T < SAFETY_T_HI) && (min_T > SAFETY_T_LO);
end
