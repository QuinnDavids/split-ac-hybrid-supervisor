function learn = layer2_learning(learn, T_in, T_in_pred, T_out, N_occ, t_hour, day_type, p)
%LAYER2_LEARNING  Update the three online learners of the hybrid framework.
%   learn = LAYER2_LEARNING(learn, T_in, T_in_pred, T_out, N_occ, t_hour, day_type, p)
%
%   Runs three updates each step (intended to be called only during the
%   p.learn_days warm-up window; the evaluation window (days p.learn_days+1
%   .. p.days) freezes the learners):
%
%     (a) Markov occupancy counts (Eq. 3.9-3.10)
%         learn.occ_counts(day_type, hour_bin, 1|2) += 1
%         -> P(occupied | day_type, hour) for the pre-cool trigger.
%
%     (b) RLS calibration of U_comp (Eq. 3.7-3.8)
%         residual = T_in_measured - T_in_predicted
%         U_est <- U_est + K_RLS * residual * sign(T_out - T_in)
%         (clipped to [0.5, 5.0] W/m^2K to stay physical)
%
%     (c) EMA preference (Eq. 3.6) -- updates ONLY when occupied
%         T_pref <- (1-alpha) * T_pref + alpha * T_in
%         (clipped to the comfort band [T_min, T_max])
%
%   Inputs
%     learn      : struct carrying U_est, dT_sol_est, T_pref, occ_counts
%     T_in       : measured indoor T this step (degC)
%     T_in_pred  : indoor T predicted by the BTM using the PREVIOUS step's
%                  state (degC). Pass NaN to skip the RLS update.
%     T_out      : outdoor T at the previous step (degC)
%     N_occ      : occupant count this step (persons)
%     t_hour     : hour-of-day, 0..24
%     day_type   : 1..7 (1=Mon, 7=Sun)
%     p          : params

    cur_occ = N_occ > 0;

    % --- (a) Markov occupancy counts ---
    hour_bin = min(24, max(1, floor(t_hour) + 1));
    occ_bin  = double(cur_occ) + 1;                   % 1 = unoccupied, 2 = occupied
    learn.occ_counts(day_type, hour_bin, occ_bin) = ...
        learn.occ_counts(day_type, hour_bin, occ_bin) + 1;

    % --- (b) RLS update of U_comp ---
    if ~isnan(T_in_pred)
        residual  = T_in - T_in_pred;                 % degC, measurement vs BTM prediction
        regressor = T_out - T_in;                     % degC, drives envelope
        if abs(regressor) > 0.5                       % avoid divide-by-near-zero
            learn.U_est = learn.U_est + p.K_RLS * residual * sign(regressor);
            learn.U_est = max(0.5, min(5.0, learn.U_est));
        end
    end

    % --- (c) EMA preference ---
    if cur_occ
        learn.T_pref = (1 - p.alpha) * learn.T_pref + p.alpha * T_in;
        learn.T_pref = max(p.T_min, min(p.T_max, learn.T_pref));
    end
end
