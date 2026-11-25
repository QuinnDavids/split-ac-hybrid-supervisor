function explore_results()
%EXPLORE_RESULTS  Deluxe interactive viewer for run_simulation.m output.
%
%   Loads results/run_simulation_results.mat (the R struct saved by
%   run_simulation.m) and opens a live MATLAB figure with:
%
%     - HVAC-type dropdown (Inverter / Bang-Bang).
%         Auto-detects whether R is in the LEGACY layout
%         (R.(season).(strategy)) or the MULTI-HVAC layout
%         (R.(hvac_type).(season).(strategy)), exactly the same detection
%         logic used in generate_html_report.m. In legacy mode this
%         dropdown is disabled and shows "Inverter (only)" so the tool
%         behaves identically to before. In multi-HVAC mode it lets you
%         flip between compressor types live, same as flipping season.
%     - Season dropdown (hot / rain)
%     - Mode toggle:
%         "Scrub"      -- a continuous two-handle RANGE SLIDER over the
%                         whole p.days-day study, so you can zoom into
%                         any window (e.g. hour 340-360, straight through
%                         a midnight), not locked to single-day boundaries.
%         "Day-locked" -- single slider, snaps to one calendar day at a
%                         time (the earlier behaviour, kept as an option).
%     - "Eval window only" checkbox -- restricts the scrub range to
%       days (p.learn_days+1 .. p.days), i.e. the window metrics.m
%       actually scores, so learn-phase behaviour is not captured
%       by accident.
%     - Two synced axes (T_in on top, P_elec below; zooming/panning one
%       moves the other, since they share an x-axis via linkaxes).
%     - A branch-aware data cursor: click any point on the hybrid trace
%       and the tooltip shows T_in, P_elec, is_on, and (for hybrid)
%       which decision branch (log.branch) was active at that step --
%       e.g. 'precool', 'setback_off', 'occupied' -- so you can screenshot
%       a moment and immediately caption WHY the controller did that.
%
%   Standard MATLAB axes toolbar (zoom/pan/data-cursor/export) is present
%   throughout -- core MATLAB (uifigure/uiaxes/uislider), no toolboxes.
%
%   Usage:
%     >> explore_results

    S = load('results/run_simulation_results.mat', 'R');
    R = S.R;
    p = sim_params('hot');   % time-base fields (dt, days, learn_days) are season-independent

    strats  = {'baseline','scheduled','hybrid'};
    colors  = {[0 0.4 0.8], [0.85 0 0], [0.6 0 0.6]};

    % ---------------- detect legacy vs multi-HVAC structure ----------------
    % Same detection convention as generate_html_report.m Section 1, so the
    % two tools stay consistent about what "the R struct" means regardless
    % of which version of run_simulation.m produced the file.
    KNOWN_SEASONS = {'hot','rain'};
    KNOWN_HVAC    = {'inverter','bangbang'};

    top_fields    = fieldnames(R);
    is_legacy     = all(ismember(top_fields, KNOWN_SEASONS));
    is_multi_hvac = all(ismember(top_fields, KNOWN_HVAC));

    if is_legacy
        hvac_types = {'inverter'};             % legacy runs are inverter-only
        seasons    = top_fields;
        getRun     = @(hvac, season, strat) R.(season).(strat);
    elseif is_multi_hvac
        hvac_types = top_fields;                % {'inverter','bangbang'}, order as stored
        seasons    = fieldnames(R.(hvac_types{1}));
        getRun     = @(hvac, season, strat) R.(hvac).(season).(strat);
    else
        error('explore_results:structure', ...
            ['Unrecognized results struct: top-level fields are {%s}, which match ' ...
             'neither the legacy {hot,rain} layout nor the multi-HVAC {inverter,bangbang} ' ...
             'layout. If run_simulation.m nests R differently, update the detection ' ...
             'logic near the top of explore_results.m.'], strjoin(top_fields, ','));
    end

    steps_per_day = 24*3600/p.dt; %#ok<NASGU>
    total_hours   = p.days * 24;

    % ---------------- main window: plots ----------------
    fig = uifigure('Name','Results Explorer','Position',[80 80 1150 720]);
    g = uigridlayout(fig, [2 1]);
    g.RowHeight = {'1x','1x'};

    ax1 = uiaxes(g); ax1.Layout.Row = 1;
    ax2 = uiaxes(g); ax2.Layout.Row = 2;
    linkaxes([ax1 ax2], 'x');     % synced zoom/pan

    dcm = datacursormode(fig);
    set(dcm, 'UpdateFcn', @cursorText);

    % ---------------- control window ----------------
    ctrl = uifigure('Name','Controls','Position',[80 820 1150 230]);
    gc = uigridlayout(ctrl, [5 5]);
    gc.RowHeight   = {30, 30, 40, 40, 30};
    gc.ColumnWidth = {70, 110, 160, 160, '1x'};

    % --- Row 1: HVAC type + season ---
    hvacLbl = uilabel(gc,'Text','HVAC type:');
    hvacLbl.Layout.Row = 1; hvacLbl.Layout.Column = 1;
    if is_multi_hvac
        hvacItems = cellfun(@hvac_display_name, hvac_types, 'UniformOutput', false);
        hvacDD = uidropdown(gc, 'Items', hvacItems, 'Value', hvacItems{1}, 'Enable', 'on');
    else
        hvacDD = uidropdown(gc, 'Items', {'Inverter (only)'}, 'Value', 'Inverter (only)', 'Enable', 'off');
    end
    hvacDD.Layout.Row = 1; hvacDD.Layout.Column = 2;

    seasonLbl = uilabel(gc,'Text','Season:');
    seasonLbl.Layout.Row = 1; seasonLbl.Layout.Column = 3;
    seasonDD = uidropdown(gc, 'Items', seasons, 'Value', seasons{1});
    seasonDD.Layout.Row = 1; seasonDD.Layout.Column = 4;

    modeNote = uilabel(gc, 'Text', ternary(is_multi_hvac, ...
        'Multi-HVAC results detected.', 'Legacy (inverter-only) results.'));
    modeNote.Layout.Row = 1; modeNote.Layout.Column = 5;

    % --- Row 2: mode switch + eval-window checkbox ---
    modeSW = uiswitch(gc, 'slider', 'Items', {'Scrub','Day-locked'}, 'Value', 'Scrub');
    modeSW.Layout.Row = 2; modeSW.Layout.Column = 1;

    evalChk = uicheckbox(gc, 'Text', 'Eval window only', 'Value', false);
    evalChk.Layout.Row = 2; evalChk.Layout.Column = 4;

    rangeInfo = uilabel(gc, 'Text', '');
    rangeInfo.Layout.Row = 2; rangeInfo.Layout.Column = 5;

    % Continuous scrubbing = TWO ordinary sliders (Start hour / End hour).
    % (uislider does not support a two-handle range Value in R2024 --
    % that is a different, newer component. Two sliders gives the same
    % scrubbing capability and is fully supported here.)
    startLbl = uilabel(gc, 'Text', 'Start (h):');
    startLbl.Layout.Row = 3; startLbl.Layout.Column = 1;
    startSlider = uislider(gc, 'Limits', [0 total_hours], ...
        'Value', p.learn_days*24, 'MajorTicks', 0:48:total_hours);
    startSlider.Layout.Row = 3; startSlider.Layout.Column = [2 5];

    endLbl = uilabel(gc, 'Text', 'End (h):');
    endLbl.Layout.Row = 4; endLbl.Layout.Column = 1;
    endSlider = uislider(gc, 'Limits', [0 total_hours], ...
        'Value', (p.learn_days+1)*24, 'MajorTicks', 0:48:total_hours);
    endSlider.Layout.Row = 4; endSlider.Layout.Column = [2 5];

    % Day-locked single slider (hidden unless in Day-locked mode)
    daySlider = uislider(gc, 'Limits', [1 p.days], 'Value', p.learn_days+1, ...
        'MajorTicks', 1:2:p.days, 'Visible', 'off');
    daySlider.Layout.Row = 5; daySlider.Layout.Column = [1 4];
    dayLabel = uilabel(gc, 'Text', sprintf('Day %d', p.learn_days+1), 'Visible','off');
    dayLabel.Layout.Row = 5; dayLabel.Layout.Column = 5;

    hvacDD.ValueChangedFcn      = @(~,~) redraw();
    seasonDD.ValueChangedFcn    = @(~,~) redraw();
    modeSW.ValueChangedFcn      = @(~,~) onModeChange();
    evalChk.ValueChangedFcn     = @(~,~) onEvalToggle();
    startSlider.ValueChangedFcn = @(~,~) onStartChange();
    endSlider.ValueChangedFcn   = @(~,~) onEndChange();
    daySlider.ValueChangedFcn   = @(~,~) redraw();

    onEvalToggle();   % sets scrub limits, then draws

    % ---------------- callbacks ----------------
    function hvac = currentHvac()
        if is_multi_hvac
            idx  = find(strcmp(hvacDD.Items, hvacDD.Value), 1);
            hvac = hvac_types{idx};
        else
            hvac = hvac_types{1};   % 'inverter', legacy
        end
    end

    function onModeChange()
        isDay = strcmp(modeSW.Value, 'Day-locked');
        startLbl.Visible    = ~isDay; startSlider.Visible = ~isDay;
        endLbl.Visible      = ~isDay; endSlider.Visible   = ~isDay;
        daySlider.Visible   = isDay;
        dayLabel.Visible    = isDay;
        redraw();
    end

    function onEvalToggle()
        if evalChk.Value
            lo = p.learn_days*24; hi = total_hours;
        else
            lo = 0; hi = total_hours;
        end
        startSlider.Limits = [lo hi];
        endSlider.Limits   = [lo hi];
        sv = min(max(startSlider.Value, lo), hi);
        ev = min(max(endSlider.Value,   lo), hi);
        if sv >= ev, sv = lo; ev = hi; end
        startSlider.Value = sv;
        endSlider.Value   = ev;
        redraw();
    end

    function onStartChange()
        if startSlider.Value >= endSlider.Value
            startSlider.Value = max(endSlider.Value - 1, startSlider.Limits(1));
        end
        redraw();
    end

    function onEndChange()
        if endSlider.Value <= startSlider.Value
            endSlider.Value = min(startSlider.Value + 1, endSlider.Limits(2));
        end
        redraw();
    end

    function redraw()
        season = seasonDD.Value;
        hvac   = currentHvac();

        if strcmp(modeSW.Value, 'Day-locked')
            d = round(daySlider.Value);
            daySlider.Value = d;
            dayLabel.Text = sprintf('Day %d%s', d, ternary(d<=p.learn_days,' (learn)',' (eval)'));
            h_lo = (d-1)*24; h_hi = d*24;
        else
            h_lo = startSlider.Value; h_hi = endSlider.Value;
        end

        k_lo = max(1, round(h_lo*3600/p.dt) + 1);
        k_hi = min(p.N, round(h_hi*3600/p.dt));
        if k_hi <= k_lo, k_hi = min(p.N, k_lo+1); end
        idx = k_lo:k_hi;
        hh  = (idx-1) * p.dt / 3600;   % absolute hours from study start

        rangeInfo.Text = sprintf('%.1f h -- %.1f h  (day %.1f -- %.1f)', ...
            h_lo, h_hi, h_lo/24+1, h_hi/24+1);

        run_b = getRun(hvac, season, 'baseline');
        run_s = getRun(hvac, season, 'scheduled');
        run_h = getRun(hvac, season, 'hybrid');
        runs  = {run_b, run_s, run_h};

        cla(ax1); hold(ax1,'on');
        plot(ax1, hh, run_b.log.T_out(idx), 'k:', 'LineWidth', 1.0, 'DisplayName','T_{out}');
        for si = 1:numel(strats)
            L = runs{si}.log;
            hLine = plot(ax1, hh, L.T_in(idx), 'Color', colors{si}, 'LineWidth', 1.4, ...
                'DisplayName', strats{si});
            hLine.UserData = struct('strategy', strats{si}, 'season', season, 'hvac', hvac, 'idx0', idx(1));
        end
        yline(ax1, p.T_min, 'g:'); yline(ax1, p.T_max, 'g:');
        eval_start_h = p.learn_days*24;
        if h_lo < eval_start_h && h_hi > eval_start_h
            xline(ax1, eval_start_h, 'k--', 'eval starts');
        end
        xlabel(ax1,'hours since study start'); ylabel(ax1,'T_{in} (degC)');
        title(ax1, sprintf('%s season%s -- indoor temperature', upper(season), hvac_title_suffix(hvac, is_multi_hvac)));
        legend(ax1, 'Location','best'); grid(ax1,'on');

        cla(ax2); hold(ax2,'on');
        for si = 1:numel(strats)
            L = runs{si}.log;
            hLine = plot(ax2, hh, L.P_elec(idx), 'Color', colors{si}, 'LineWidth', 1.4, ...
                'DisplayName', strats{si});
            hLine.UserData = struct('strategy', strats{si}, 'season', season, 'hvac', hvac, 'idx0', idx(1));
        end
        if h_lo < eval_start_h && h_hi > eval_start_h
            xline(ax2, eval_start_h, 'k--', 'eval starts');
        end
        xlabel(ax2,'hours since study start'); ylabel(ax2,'P_{elec} (W)');
        title(ax2, sprintf('%s season%s -- electrical power', upper(season), hvac_title_suffix(hvac, is_multi_hvac)));
        legend(ax2, 'Location','best'); grid(ax2,'on');

        xlim(ax1, [hh(1) hh(end)]);
        xlim(ax2, [hh(1) hh(end)]);
    end

    % ---------------- branch-aware data cursor ----------------
    function txt = cursorText(~, event)
        ud = get(event.Target, 'UserData');
        if isempty(ud)
            txt = {sprintf('x = %.2f', event.Position(1)), sprintf('y = %.2f', event.Position(2))};
            return;
        end
        L = getRun(ud.hvac, ud.season, ud.strategy).log;
        hh_click = event.Position(1);
        k = round(hh_click*3600/p.dt) + 1;
        k = min(max(k,1), p.N);

        txt = { sprintf('%s (%s)%s', ud.strategy, ud.season, hvac_title_suffix(ud.hvac, is_multi_hvac)), ...
                sprintf('hour = %.2f  (day %.1f)', hh_click, hh_click/24+1), ...
                sprintf('T_{in} = %.2f degC', L.T_in(k)), ...
                sprintf('P_{elec} = %.0f W', L.P_elec(k)), ...
                sprintf('AC on = %d', L.is_on(k)) };
        if isfield(L,'branch')
            txt{end+1} = sprintf('branch = %s', L.branch(k));
        end
    end

    function s = ternary(cond,a,b)
        if cond, s = a; else, s = b; end
    end
end

% ============ module-level helpers (no shared-state closure needed) ========
function name = hvac_display_name(hvac)
    switch hvac
        case 'inverter', name = 'Inverter';
        case 'bangbang', name = 'Bang-Bang';
        otherwise,       name = hvac;
    end
end

function suf = hvac_title_suffix(hvac, is_multi_hvac)
    % Only annotate titles/tooltips with HVAC type once there's more than
    % one type to distinguish -- keeps legacy-mode titles unchanged.
    if is_multi_hvac
        suf = sprintf(' (%s)', hvac_display_name(hvac));
    else
        suf = '';
    end
end