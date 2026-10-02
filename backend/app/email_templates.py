import html

def _escape(val):
    if val is None:
        return ""
    return html.escape(str(val))

def _fmt_num(val, decimals=2):
    if val is None:
        return "-"
    try:
        val_f = float(val)
        if val_f != val_f:  # check for nan
            return "-"
        # For scores, round to whole numbers if we want. 
        # But the prompt says "scores to whole numbers, metric values to at most 2 decimals".
        if decimals == 0:
            return str(round(val_f))
        
        # At most 2 decimals
        formatted = f"{val_f:.{decimals}f}".rstrip('0').rstrip('.')
        if formatted == "":
            return "0"
        if formatted == "-0":
            return "0"
        return formatted
    except (ValueError, TypeError):
        return "-"

def _format_metric_table_html(metrics, include_previous=True):
    rows = []
    for m in metrics:
        val_str = _fmt_num(m.get('value'), 2)
        prev_str = _fmt_num(m.get('previous'), 2)
        pro_str = _escape(m.get('pro'))
        unit_str = _escape(m.get('unit'))
        direction = m.get('direction')
        
        marker = ""
        if direction == "better":
            marker = " (Better)"
        elif direction == "worse":
            marker = " (Worse)"
        
        prev_cell = f"<td style='padding: 8px; border-bottom: 1px solid #ddd;'>{prev_str} {unit_str}</td>" if include_previous else ""
        
        row = f"""
        <tr>
            <td style='padding: 8px; border-bottom: 1px solid #ddd;'>{_escape(m.get('label'))}</td>
            <td style='padding: 8px; border-bottom: 1px solid #ddd;'>{val_str} {unit_str}{marker}</td>
            {prev_cell}
            <td style='padding: 8px; border-bottom: 1px solid #ddd;'>{pro_str} {unit_str}</td>
        </tr>
        """
        rows.append(row)
    
    prev_header = "<th style='padding: 8px; text-align: left; border-bottom: 2px solid #ddd;'>Previous Avg</th>" if include_previous else ""
    
    return f"""
    <table style="width: 100%; border-collapse: collapse; margin-top: 16px; margin-bottom: 16px;">
        <thead>
            <tr>
                <th style='padding: 8px; text-align: left; border-bottom: 2px solid #ddd;'>Metric</th>
                <th style='padding: 8px; text-align: left; border-bottom: 2px solid #ddd;'>Value</th>
                {prev_header}
                <th style='padding: 8px; text-align: left; border-bottom: 2px solid #ddd;'>Pro Target</th>
            </tr>
        </thead>
        <tbody>
            {"".join(rows)}
        </tbody>
    </table>
    """

def _format_metric_table_text(metrics, include_previous=True):
    lines = []
    for m in metrics:
        val_str = _fmt_num(m.get('value'), 2)
        prev_str = _fmt_num(m.get('previous'), 2)
        pro_str = str(m.get('pro', '-'))
        unit_str = str(m.get('unit', ''))
        direction = m.get('direction')
        
        marker = ""
        if direction == "better":
            marker = " (Better)"
        elif direction == "worse":
            marker = " (Worse)"
            
        line = f"- {m.get('label')}: {val_str} {unit_str}{marker} | Pro: {pro_str} {unit_str}"
        if include_previous:
            line += f" | Prev: {prev_str} {unit_str}"
        lines.append(line)
    return "\n".join(lines)


def session_email(user_name: str, sport_label: str, session: dict, comparison: dict) -> tuple[str, str, str]:
    safe_name = _escape(user_name)
    safe_sport = _escape(sport_label)
    
    score = _fmt_num(session.get('score'), 0)
    reps = session.get('rep_count', 0)
    duration = _fmt_num(session.get('duration_s', 0), 0)
    
    score_delta = comparison.get('score_delta')
    prev_avg = comparison.get('previous_avg_score')
    
    delta_text = ""
    delta_html = ""
    if score_delta is not None and prev_avg is not None:
        delta_val = _fmt_num(score_delta, 1)
        direction_word = "up" if float(score_delta) >= 0 else "down"
        delta_val = delta_val.replace("-", "")
        delta_text = f" This is {direction_word} {delta_val} from your previous average of {_fmt_num(prev_avg, 0)}."
        delta_html = _escape(delta_text)

    metrics = comparison.get('metrics', [])
    cues = session.get('top_cues', [])
    
    subject = f"Your latest {sport_label} session score: {score}"
    
    html_body = f"""
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="margin-top: 0;">Hi {safe_name},</h2>
        <p>Great job getting out there! Here is your latest {safe_sport} report.</p>
        <p><strong>Session Score: {score}</strong>{delta_html}</p>
        <p>You completed {reps} reps in {duration} seconds.</p>
        
        <h3>Metrics Breakdown</h3>
        {_format_metric_table_html(metrics, include_previous=True)}
        
        <h3>What to work on next</h3>
        <ul>
            {"".join(f"<li>{_escape(c)}</li>" for c in cues)}
        </ul>
        <p>Keep up the great work!</p>
    </div>
    """
    
    text_body = f"""Hi {user_name},

Great job getting out there! Here is your latest {sport_label} report.

Session Score: {score}{delta_text}
You completed {reps} reps in {duration} seconds.

Metrics Breakdown:
{_format_metric_table_text(metrics, include_previous=True)}

What to work on next:
"""
    for c in cues:
        text_body += f"- {c}\n"
        
    text_body += "\nKeep up the great work!\n"
    
    return subject, html_body, text_body


def checkpoint_email(user_name: str, sport_label: str, checkpoint: dict) -> tuple[str, str, str]:
    safe_name = _escape(user_name)
    safe_sport = _escape(sport_label)
    
    avg_score = _fmt_num(checkpoint.get('avg_score'), 0)
    prev_avg = checkpoint.get('previous_avg_score')
    
    delta_text = ""
    delta_html = ""
    if prev_avg is not None and checkpoint.get('avg_score') is not None:
        diff = float(checkpoint.get('avg_score')) - float(prev_avg)
        direction_word = "up" if diff >= 0 else "down"
        diff_str = _fmt_num(abs(diff), 1)
        delta_text = f" This is {direction_word} {diff_str} from your previous block's average of {_fmt_num(prev_avg, 0)}."
        delta_html = _escape(delta_text)

    metrics = checkpoint.get('metrics', [])
    cues = checkpoint.get('focus_cues', [])
    
    subject = f"Your {sport_label} progress checkpoint: Score {avg_score}"
    
    html_body = f"""
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px;">
        <h2 style="margin-top: 0;">Hi {safe_name},</h2>
        <p>You've completed another block of {safe_sport} sessions! Here is your progress update.</p>
        <p><strong>Block Average Score: {avg_score}</strong>{delta_html}</p>
        
        <h3>Metrics Breakdown</h3>
        {_format_metric_table_html(metrics, include_previous=True)}
        
        <h3>Focus areas for your next sessions</h3>
        <ul>
            {"".join(f"<li>{_escape(c)}</li>" for c in cues)}
        </ul>
        <p>Keep up the great work!</p>
    </div>
    """
    
    text_body = f"""Hi {user_name},

You've completed another block of {sport_label} sessions! Here is your progress update.

Block Average Score: {avg_score}{delta_text}

Metrics Breakdown:
{_format_metric_table_text(metrics, include_previous=True)}

Focus areas for your next sessions:
"""
    for c in cues:
        text_body += f"- {c}\n"
        
    text_body += "\nKeep up the great work!\n"
    
    return subject, html_body, text_body
