WITH RECURSIVE 

rsi_base AS (
    -- Compute gain/loss and row numbers
    SELECT
        date,
        close,
        LAG(close) OVER (ORDER BY date) AS prev_close,
        GREATEST(close - LAG(close) OVER (ORDER BY date), 0) AS gain,
        GREATEST(LAG(close) OVER (ORDER BY date) - close, 0) AS loss,
        ROW_NUMBER() OVER (ORDER BY date) AS rn
    FROM stock_prices
),

anchor AS (
    -- Row 14: compute the FIRST 14-day averages
    SELECT
        date,
        close,
        gain,
        loss,
        rn,
        (SELECT SUM(gain) FROM rsi_base WHERE rn BETWEEN 1 AND 14) / 14.0 AS avg_gain,
        (SELECT SUM(loss) FROM rsi_base WHERE rn BETWEEN 1 AND 14) / 14.0 AS avg_loss
    FROM rsi_base
    WHERE rn = 14
),

rsi_recursive AS (
    -- Start recursion from row 14
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

    -- For day 15: use the anchor averages (no smoothing)
    -- For day 16+: apply Wilder smoothing
    SELECT
        b.date,
        b.close,
        b.gain,
        b.loss,
        b.rn,

        CASE WHEN r.rn = 14 THEN r.avg_gain
             ELSE (r.avg_gain * 13 + b.gain) / 14.0
        END AS avg_gain,

        CASE WHEN r.rn = 14 THEN r.avg_loss
             ELSE (r.avg_loss * 13 + b.loss) / 14.0
        END AS avg_loss

    FROM rsi_recursive r
    JOIN rsi_base b
      ON b.rn = r.rn + 1
),

final AS (
    SELECT
        b.date,
        b.close,
        b.gain,
        b.loss,

        -- bring avg_gain/loss in only after recursion reaches those rows
        CASE WHEN b.rn < 15 THEN NULL ELSE r.avg_gain END AS avg_gain,
        CASE WHEN b.rn < 15 THEN NULL ELSE r.avg_loss END AS avg_loss,

        -- RS = avg_gain / avg_loss
        CASE 
            WHEN b.rn < 15 THEN NULL
            WHEN r.avg_loss = 0 THEN NULL
            ELSE r.avg_gain / r.avg_loss
        END AS rs,

        -- RSI formula
        CASE 
            WHEN b.rn < 15 THEN NULL
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
