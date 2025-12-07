WITH RECURSIVE
price_with_rn AS (
    SELECT 
        date,
        close,
        ROW_NUMBER() OVER (ORDER BY date) AS rn
    FROM stock_prices
),
EMA_recursive AS (
    -- Base case: row 1
    SELECT 
        date,
        close,
        rn,
        NULL::DOUBLE PRECISION AS sma,
        NULL::DOUBLE PRECISION AS ema,
        ARRAY[close] AS window_close
    FROM price_with_rn
    WHERE rn = 1
    
    UNION ALL
    
    SELECT 
        p.date,
        p.close,
        p.rn,
        -- SMA: calculated when we have exactly 10 values in the window
        CASE
            WHEN array_length(e.window_close || p.close, 1) >= 10 THEN (
                SELECT AVG(x) 
                FROM UNNEST(
                    CASE 
                        WHEN array_length(e.window_close || p.close, 1) = 10 
                        THEN e.window_close || p.close
                        ELSE (e.window_close[2:10] || p.close)
                    END
                ) AS x
            )
        END AS sma,
        -- EMA calculation
        CASE
            -- Row 10: EMA = SMA of first 10 values
            WHEN p.rn = 10 THEN (
                SELECT AVG(x) 
                FROM UNNEST(e.window_close || p.close) AS x
            )
            -- Row 11+: EMA = (Close - Previous EMA) * smoothing + Previous EMA
            WHEN p.rn > 10 THEN 
                (p.close - e.ema) * (2.0/11.0) + e.ema
        END AS ema,
        -- Maintain sliding window of 10 prices for SMA
        CASE
            WHEN array_length(e.window_close, 1) < 10
            THEN e.window_close || p.close
            ELSE (e.window_close[2:10] || p.close)
        END AS window_close
    FROM EMA_recursive e
    JOIN price_with_rn p ON p.rn = e.rn + 1
)
SELECT 
    date,
    close,
    sma,
	Case
		When rn > 10
		Then (2.0/(10+1)) 
	End As smooth_const,
    ema
FROM EMA_recursive
ORDER BY date;