DROP FUNCTION IF EXISTS rsi_wilder(text, integer);

CREATE OR REPLACE FUNCTION rsi_wilder(
    prices_table TEXT,
    period INTEGER DEFAULT 14
)
RETURNS TABLE (
    date DATE,
    close NUMERIC,
    gain NUMERIC,
    loss NUMERIC,
    avg_gain NUMERIC,
    avg_loss NUMERIC,
    rs NUMERIC,
    rsi NUMERIC,
    rn BIGINT
)
LANGUAGE plpgsql AS
$$
BEGIN
RETURN QUERY EXECUTE format($sql$

WITH RECURSIVE 

rsi_base AS (
    SELECT
        date,
        close::numeric,
        LAG(close) OVER (ORDER BY date) AS prev_close,
        GREATEST(close - LAG(close) OVER (ORDER BY date), 0)::numeric AS gain,
        GREATEST(LAG(close) OVER (ORDER BY date) - close, 0)::numeric AS loss,
        ROW_NUMBER() OVER (ORDER BY date) AS rn
    FROM %I
),

anchor AS (
    SELECT
        date,
        close,
        gain,
        loss,
        rn,
        (SELECT SUM(gain)::numeric FROM rsi_base WHERE rn BETWEEN 1 AND %s) / %s::numeric AS avg_gain,
        (SELECT SUM(loss)::numeric FROM rsi_base WHERE rn BETWEEN 1 AND %s) / %s::numeric AS avg_loss
    FROM rsi_base
    WHERE rn = %s
),

rsi_recursive AS (
    SELECT
        date,
        close,
        gain,
        loss,
        rn,
        avg_gain,
        avg_loss
    FROM anchor

    UNION ALL

    SELECT
        b.date,
        b.close,
        b.gain,
        b.loss,
        b.rn,

        CASE 
            WHEN r.rn = %s THEN r.avg_gain
            ELSE (r.avg_gain * (%s - 1) + b.gain) / %s::numeric
        END AS avg_gain,

        CASE 
            WHEN r.rn = %s THEN r.avg_loss
            ELSE (r.avg_loss * (%s - 1) + b.loss) / %s::numeric
        END AS avg_loss

    FROM rsi_recursive r
    JOIN rsi_base b ON b.rn = r.rn + 1
),

final AS (
    SELECT
        b.date,
        b.close,
        b.gain,
        b.loss,

        CASE WHEN b.rn < (%s + 1) THEN NULL ELSE r.avg_gain END AS avg_gain,
        CASE WHEN b.rn < (%s + 1) THEN NULL ELSE r.avg_loss END AS avg_loss,

        CASE 
            WHEN b.rn < (%s + 1) THEN NULL
            WHEN r.avg_loss = 0 THEN NULL
            ELSE r.avg_gain / r.avg_loss
        END AS rs,

        CASE 
            WHEN b.rn < (%s + 1) THEN NULL
            WHEN r.avg_loss = 0 THEN 100
            ELSE 100 - (100 / (1 + (r.avg_gain / r.avg_loss)))
        END AS rsi,

        b.rn
    FROM rsi_base b
    LEFT JOIN rsi_recursive r ON b.rn = r.rn
)

SELECT *
FROM final
ORDER BY rn;

$sql$,
    prices_table,  -- %I
    period, period, -- sums/divisors in anchor
    period, period, -- sums/divisors in anchor (repeated)
    period,          -- WHERE rn = period
    period,          -- WHEN r.rn = period (avg_gain)
    period, period,  -- (period-1) and / period (avg_gain smoothing)
    period,          -- WHEN r.rn = period (avg_loss)
    period, period,  -- (period-1) and / period (avg_loss smoothing)
    period,          -- CASE WHEN b.rn < period THEN NULL ...
    period,          -- same
    period,          -- rs check uses period+1
    period           -- rsi check uses period+1
);
END;
$$;
