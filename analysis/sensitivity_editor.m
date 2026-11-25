function sensitivity_editor()
%SENSITIVITY_EDITOR  Interactive robustness explorer.
%
%   run_sensitivity.m tests fixed points (+/-50% C_th, +/-20% U_comp,
%   +/-15% COP_nom). This dashboard lets you drag CONTINUOUS sliders over
%   those same ranges (and a little beyond, for exploration) and see, live,
%   whether the two robustness conditions of run_sensitivity.m still hold:
%     (1) Hybrid ESI stays POSITIVE vs baseline
%     (2) Hybrid TCSR stays >= both baseline and scheduled TCSR
%   for the currently selected season.
%
%   Each "Run" reruns baseline+scheduled+hybrid on ONE season with the
%   perturbed params, on the same seeded occupancy as the real study.
%
%   Usage:
%     >> sensitivity_editor

    p0 = sim_params('hot');

    fig = uifigure('Name','Sensitivity Explorer (Port Harcourt, Tier 2)','Position',[80 80 1150 650]);
    g = uigridlayout(fig,[2 1]);
    g.RowHeight = {'1x','1x'};
    axBar  = uiaxes(g); axBar.Layout.Row = 1;
    axTcsr = uiaxes(g); axTcsr.Layout.Row = 2;

    ctrl = uifigure('Name','Sensitivity Controls','Position',[80 750 1150 260]);
    gc = uigridlayout(ctrl, [6 3]);
    gc.RowHeight   = {30,30,30,30,30,40};
    gc.ColumnWidth = {230, '1x', 90};

    seasonLbl = uilabel(gc,'Text','Season:');
    seasonLbl.Layout.Row = 1; seasonLbl.Layout.Column = 1;
    seasonDD = uidropdown(gc, 'Items', {'hot','rain'}, 'Value','hot');
    seasonDD.Layout.Row = 1; seasonDD.Layout.Column = [2 3];

    [sCth, lblCth] = addRow(gc, 2, sprintf('C_{th} deviation %% (study sweep +/-50%%)'), -70, 70, 0);
    [sUc,  lblUc ] = addRow(gc, 3, sprintf('U_{comp} deviation %% (study sweep +/-20%%)'), -30, 30, 0);
    [sCop, lblCop] = addRow(gc, 4, sprintf('COP_{nom} deviation %% (study sweep +/-15%%)'), -25, 25, 0);

    statusLbl = uilabel(gc, 'Text','Ready.');
    statusLbl.Layout.Row = 5; statusLbl.Layout.Column = [1 3];

    runBtn = uibutton(gc, 'Text','Run', 'ButtonPushedFcn', @(~,~) runExperiment());
    runBtn.Layout.Row = 6; runBtn.Layout.Column = [1 3];

    runExperiment();

    function [s, vlabel] = addRow(parent, row, labelTxt, lo, hi, initVal)
        lbl = uilabel(parent,'Text',labelTxt);
        lbl.Layout.Row = row; lbl.Layout.Column = 1;
        s = uislider(parent, 'Limits',[lo hi], 'Value', initVal);
        s.Layout.Row = row; s.Layout.Column = 2;
        vlabel = uilabel(parent,'Text', sprintf('%+.0f%%',initVal));
        vlabel.Layout.Row = row; vlabel.Layout.Column = 3;
        s.ValueChangedFcn = @(src,~) set(vlabel,'Text', sprintf('%+.0f%%', src.Value));
    end

    function runExperiment()
        statusLbl.Text = 'Running...'; drawnow;

        season = seasonDD.Value;
        p = sim_params(season);
        p.C_th    = p0.C_th    * (1 + sCth.Value/100);
        p.U_comp  = p0.U_comp  * (1 + sUc.Value/100);
        p.COP_nom = p0.COP_nom * (1 + sCop.Value/100);

        [N_occ, ~] = occupancy_profile(p);   % re-seeded internally (p.seed), matches study
        T_out = weather_profile(p);

        log_b = strategy_baseline (T_out, N_occ, p);
        log_s = strategy_scheduled(T_out, N_occ, p);
        log_h = strategy_hybrid   (T_out, N_occ, p);

        m_b0   = metrics(log_b, p);
        E_base = m_b0.E_kWh;
        m_b = metrics(log_b, p, E_base);
        m_s = metrics(log_s, p, E_base);
        m_h = metrics(log_h, p, E_base);

        pass_esi  = m_h.ESI > 0;
        pass_tcsr = m_h.TCSR >= max(m_b.TCSR, m_s.TCSR);

        cla(axBar);
        bar(axBar, categorical({'Baseline','Scheduled','Hybrid'}), [m_b.E_kWh, m_s.E_kWh, m_h.E_kWh]);
        ylabel(axBar,'E (kWh), eval window');
        title(axBar, sprintf('%s season -- C_{th}=%.0f%% U_{comp}=%.0f%% COP_{nom}=%.0f%%  | Hybrid ESI=%+.2f%% [%s]', ...
            upper(season), sCth.Value, sUc.Value, sCop.Value, m_h.ESI, ternary(pass_esi,'PASS','FAIL')));
        grid(axBar,'on');

        cla(axTcsr);
        bar(axTcsr, categorical({'Baseline','Scheduled','Hybrid'}), [m_b.TCSR, m_s.TCSR, m_h.TCSR]);
        ylabel(axTcsr,'TCSR (%), eval window');
        title(axTcsr, sprintf('Comfort satisfaction -- Hybrid best-in-class: %s', ternary(pass_tcsr,'PASS','FAIL')));
        grid(axTcsr,'on');

        statusLbl.Text = sprintf(['Robustness: ESI>0 [%s]   TCSR best-in-class [%s]   ' ...
            '(Baseline TCSR=%.1f%%, Scheduled TCSR=%.1f%%, Hybrid TCSR=%.1f%%)'], ...
            ternary(pass_esi,'PASS','FAIL'), ternary(pass_tcsr,'PASS','FAIL'), ...
            m_b.TCSR, m_s.TCSR, m_h.TCSR);
    end

    function s = ternary(c,a,b), if c, s=a; else, s=b; end, end
end
