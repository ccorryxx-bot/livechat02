/*
  # Create Daily Stats View for Analytics Dashboard

  1. New View
    - `daily_stats`: Aggregated statistics for the analytics dashboard
      - date (date)
      - total_sessions (int)
      - ai_handled (int)
      - manual_handled (int)
      - ai_escalation_count (int)
      - avg_wait_seconds (numeric)
      - avg_csat (numeric)
      - top_issue_category (text)

  2. Purpose
    - Provides daily metrics for the agent dashboard's analytics panel
    - Refreshes automatically based on live data
*/

CREATE OR REPLACE VIEW daily_stats AS
WITH session_counts AS (
  SELECT
    DATE(created_at) as stat_date,
    COUNT(*) as total_sessions,
    COUNT(*) FILTER (WHERE mode = 'ai') as ai_handled,
    COUNT(*) FILTER (WHERE mode = 'manual') as manual_handled,
    COUNT(*) FILTER (WHERE escalated_from_ai = true) as ai_escalation_count,
    AVG(customer_wait_seconds) FILTER (WHERE customer_wait_seconds IS NOT NULL) as avg_wait_seconds,
    AVG(csat_rating) FILTER (WHERE csat_rating IS NOT NULL) as avg_csat
  FROM chat_sessions
  GROUP BY DATE(created_at)
),
category_counts AS (
  SELECT
    DATE(created_at) as stat_date,
    issue_category,
    COUNT(*) as cat_count,
    ROW_NUMBER() OVER (PARTITION BY DATE(created_at) ORDER BY COUNT(*) DESC) as rn
  FROM chat_sessions
  GROUP BY DATE(created_at), issue_category
),
top_categories AS (
  SELECT stat_date, issue_category as top_category
  FROM category_counts
  WHERE rn = 1
)
SELECT
  sc.stat_date as date,
  sc.total_sessions,
  sc.ai_handled,
  sc.manual_handled,
  sc.ai_escalation_count,
  ROUND(sc.avg_wait_seconds, 2) as avg_wait_seconds,
  ROUND(sc.avg_csat, 2) as avg_csat,
  tc.top_category as top_issue_category
FROM session_counts sc
LEFT JOIN top_categories tc ON sc.stat_date = tc.stat_date
ORDER BY sc.stat_date DESC;

-- Allow anyone to read the view
GRANT SELECT ON daily_stats TO anon;
GRANT SELECT ON daily_stats TO authenticated;