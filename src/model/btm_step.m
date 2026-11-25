function [T_in_new, Q] = btm_step(T_in, T_out, N_occ, Q_cool, hour_of_day, p)
%BTM_STEP  Advance the single-zone Building Thermal Model by one Euler step.
%   [T_in_new, Q] = BTM_STEP(T_in, T_out, N_occ, Q_cool, hour_of_day, p)
%
%   Inputs
%     T_in        : current indoor temperature       (degC)
%     T_out       : outdoor temperature this step    (degC)
%     N_occ       : current occupant count           (persons)
%     Q_cool      : cooling heat removal rate >= 0   (W)   from HEM
%     hour_of_day : 0-24, used to gate solar gain    (h)
%     p           : params struct
%
%   Outputs
%     T_in_new : indoor temperature after dt seconds (degC)            % Eq. 3.24
%     Q        : struct of instantaneous heat flows for logging:
%                  Q.env, Q.int, Q.sol, Q.cool                          (W)
%
%   Governing equations (Chapter 3):
%     Q_env = U_comp * A_env * (T_out - T_in)                          % Eq. 3.18
%     Q_env_eff = Q_env * (1 + f_lat)        if p.use_latent (rainy)   % Eq. 3.19
%     Q_int = N_occ * q_met + P_equip                                  % Eq. 3.20
%     Q_sol = solar_factor * U_comp * A_roof * dT_sol  (10:00-16:00)   % Eq. 3.21
%     dT/dt = (Q_env + Q_int + Q_sol - Q_cool) / C_th                  % Eq. 3.23
%     T_in_new = T_in + dt * dT/dt                                     % Eq. 3.24

    % --- Envelope conduction (Eq. 3.18) ---
    Q_env = p.U_comp * p.A_env * (T_out - T_in);

    % --- Latent adjustment in rainy season only (Eq. 3.19) ---
    if p.use_latent
        Q_env = Q_env * (1 + p.f_lat);
    end

    % --- Internal gains (Eq. 3.20) ---
    Q_int = N_occ * p.q_met + p.P_equip;

    % --- Solar gain, daylight window 10:00-16:00 (Eq. 3.21) ---
    if hour_of_day >= 10 && hour_of_day < 16
        Q_sol = p.solar_factor * p.U_comp * p.A_roof * p.dT_sol;
    else
        Q_sol = 0;
    end

    % --- Euler advance (Eq. 3.23 + Eq. 3.24) ---
    dTdt    = (Q_env + Q_int + Q_sol - Q_cool) / p.C_th;
    T_in_new = T_in + p.dt * dTdt;

    Q.env  = Q_env;
    Q.int  = Q_int;
    Q.sol  = Q_sol;
    Q.cool = Q_cool;
end
