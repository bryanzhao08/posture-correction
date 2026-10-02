import pytest
from app.email_templates import session_email, checkpoint_email

def test_session_email_normal():
    session = {
        "score": 85.5,
        "rep_count": 20,
        "duration_s": 120.4,
        "top_cues": ["Keep your head down", "Follow through"]
    }
    comparison = {
        "previous_avg_score": 80.0,
        "score_delta": 5.5,
        "metrics": [
            {
                "id": "tempo", "label": "Tempo", "unit": "ratio",
                "value": 3.1, "previous": 2.9, "pro": 3.0, "direction": "better"
            }
        ]
    }
    
    subject, html, text = session_email("Alice", "Golf", session, comparison)
    assert "86" in subject
    assert "86" in html
    assert "86" in text
    assert "5.5" in html
    assert "up 5.5" in text
    assert "Tempo" in html
    assert "(Better)" in html
    assert "Keep your head down" in html
    assert "None" not in html
    assert "nan" not in html
    assert "None" not in text
    assert "nan" not in text

def test_session_email_first_session_no_previous():
    session = {
        "score": 75.0,
        "rep_count": 10,
        "duration_s": 60,
        "top_cues": ["Good start"]
    }
    comparison = {
        "previous_avg_score": None,
        "score_delta": None,
        "metrics": [
            {
                "id": "tempo", "label": "Tempo", "unit": "ratio",
                "value": 2.5, "previous": None, "pro": 3.0, "direction": None
            }
        ]
    }
    
    subject, html, text = session_email("Bob", "Tennis", session, comparison)
    assert "75" in subject
    assert "None" not in html
    assert "nan" not in html
    assert "None" not in text
    assert "nan" not in text
    assert "Good start" in html
    assert "-" in html # the missing previous value

def test_checkpoint_email_normal():
    checkpoint = {
        "avg_score": 88.0,
        "previous_avg_score": 82.0,
        "metrics": [
            {
                "id": "speed", "label": "Speed", "unit": "mph",
                "value": 100.5, "previous": 95.0, "pro": 110.0, "direction": "better"
            }
        ],
        "focus_cues": ["More rotation"]
    }
    subject, html, text = checkpoint_email("Charlie", "Basketball", checkpoint)
    assert "88" in subject
    assert "up 6" in text
    assert "None" not in html
    assert "nan" not in html

def test_checkpoint_email_first():
    checkpoint = {
        "avg_score": 80.0,
        "previous_avg_score": None,
        "metrics": [
            {
                "id": "speed", "label": "Speed", "unit": "mph",
                "value": 100.5, "previous": None, "pro": 110.0, "direction": None
            }
        ],
        "focus_cues": ["More rotation"]
    }
    subject, html, text = checkpoint_email("Charlie", "Basketball", checkpoint)
    assert "80" in subject
    assert "None" not in html
    assert "nan" not in html
    assert "None" not in text
    assert "nan" not in text

def test_html_escaping():
    session = {
        "score": 90,
        "rep_count": 5,
        "duration_s": 30,
        "top_cues": ["<script>alert('cue')</script>"]
    }
    comparison = {
        "previous_avg_score": 85,
        "score_delta": 5,
        "metrics": [
            {
                "id": "hack", "label": "<img src=x onerror=alert(1)>", "unit": "x",
                "value": 10, "previous": 5, "pro": 15, "direction": "better"
            }
        ]
    }
    subject, html, text = session_email("<script>alert(1)</script>", "G<o>lf", session, comparison)
    
    assert "<script>alert(1)</script>" not in html
    assert "&lt;script&gt;alert(1)&lt;/script&gt;" in html
    assert "<img src=x" not in html
    assert "&lt;img src=x" in html
    assert "<script>alert('cue')</script>" not in html
    assert "&lt;script&gt;alert(&#x27;cue&#x27;)&lt;/script&gt;" in html

