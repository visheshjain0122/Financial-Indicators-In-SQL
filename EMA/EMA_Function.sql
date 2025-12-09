DROP FUNCTION IF EXISTS calculate_ema(text, integer);

CREATE OR REPLACE FUNCTION calculate_ema(
    prices_table TEXT,
    period INTEGER DEFAULT 10
)
RETURNS TABLE (
    date DATE,
    close DOUBLE PRECISION,
    sma DOUBLE PRECISION,
    smooth_const DOUBLE PRECISION,
    ema DOUBLE PRECISION
)
LANGUAGE plpgsql AS
$$
DECLARE
    -- Calculate the smoothing factor once
    smoothing_factor DOUBLE PRECISION := 2.0 / (period + 1.0);
BEGIN
    RETURN QUERY EXECUTE format($sql$

    WITH RECURSIVE
    price_with_rn AS (
        SELECT
            date,
            close::DOUBLE PRECISION,
            ROW_NUMBER() OVER (ORDER BY date) AS rn
        FROM %I -- 1: prices_table
    ),
    EMA_recursive AS (
        -- Anchor member (Base case: row 1)
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

        -- Recursive member
        SELECT
            p.date,
            p.close,
            p.rn,
            -- CORRECTED SMA CALCULATION: Recalculates on every step where window is full (rn >= period)
            CASE
                WHEN array_length(e.window_close || p.close, 1) >= %s THEN ( -- 2: period
                    SELECT AVG(x)
                    FROM UNNEST(
                        CASE
                            WHEN array_length(e.window_close || p.close, 1) = %s -- 3: period
                            THEN e.window_close || p.close
                            ELSE (e.window_close[2:%s] || p.close) -- 4: period
                        END
                    ) AS x
                )
            END AS sma, -- Note: No COALESCE here, SMA is NULL until rn >= period

            -- EMA calculation
            CASE
                -- Row 'period': EMA = SMA of the first 'period' values
                WHEN p.rn = %s THEN ( -- 5: period
                    SELECT AVG(x)
                    FROM UNNEST(e.window_close || p.close) AS x
                )
                -- Row 'period' + 1 onwards: EMA = (Close - Previous EMA) * smoothing + Previous EMA
                WHEN p.rn > %s THEN -- 6: period
                    (p.close - e.ema) * %s + e.ema -- 7: smoothing_factor
            END AS ema,

            -- Maintain sliding window
            CASE
                WHEN array_length(e.window_close, 1) < %s -- 8: period
                THEN e.window_close || p.close
                ELSE (e.window_close[2:%s] || p.close) -- 9: period
            END AS window_close
        FROM EMA_recursive e
        JOIN price_with_rn p ON p.rn = e.rn + 1
    )
    SELECT
        date,
        close,
        sma,
        CASE
            WHEN rn > %s -- 10: period
            THEN %s::DOUBLE PRECISION -- 11: smoothing_factor (FIXED: ::DOUBLE PRECISION cast)
        END AS smooth_const,
        ema
    FROM EMA_recursive
    ORDER BY date;

    $sql$,
        prices_table,
        period,
        period,
        period,
        period,
        period,
        smoothing_factor,
        period,
        period,
        period,
        smoothing_factor
    );

END;
$$;