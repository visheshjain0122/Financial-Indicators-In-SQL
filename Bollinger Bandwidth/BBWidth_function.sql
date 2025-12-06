DROP FUNCTION IF EXISTS bollinger_bandwidth(text, integer);

CREATE OR REPLACE FUNCTION bollinger_bandwidth(
    prices_table TEXT,
    period INTEGER DEFAULT 10
)
RETURNS TABLE (
    date DATE,
    close NUMERIC,
    sma NUMERIC,
    std NUMERIC,
    upper_band NUMERIC,
    lower_band NUMERIC,
    bandwidth NUMERIC
)
LANGUAGE plpgsql AS
$$
BEGIN
    RETURN QUERY EXECUTE format($sql$

WITH RECURSIVE 

bbwidth AS (

    -- Anchor row
    SELECT
        s.date,
        s.close::numeric,
        ARRAY[s.close::numeric] AS window_close
    FROM %I s
    WHERE s.date = (SELECT MIN(date) FROM %I)

    UNION ALL

    -- Recursive rows
    SELECT
        s.date,
        s.close::numeric,
        CASE
            WHEN array_length(b.window_close, 1) < %s
                THEN b.window_close || s.close::numeric
            ELSE (b.window_close[2:%s] || s.close::numeric)
        END AS window_close
    FROM bbwidth b
    JOIN %I s
        ON s.date = (
            SELECT MIN(date)
            FROM %I
            WHERE date > b.date
        )
),

bbwidth_calc AS (
    SELECT
        date,
        close,
        window_close,
        CASE WHEN array_length(window_close, 1) = %s
            THEN (
                SELECT AVG(x::numeric)::numeric
                FROM unnest(window_close) AS x
            )
        END AS sma,
        CASE WHEN array_length(window_close, 1) = %s
            THEN (
                SELECT STDDEV_SAMP(x::numeric)::numeric
                FROM unnest(window_close) AS x
            )
        END AS std
    FROM bbwidth
)

SELECT
    date,
    close,
    sma,
    std,
    (sma + 2*std) AS upper_band,
    (sma - 2*std) AS lower_band,
    CASE WHEN sma IS NOT NULL AND std IS NOT NULL
        THEN (4*std / sma) * 100
    END AS bandwidth
FROM bbwidth_calc
ORDER BY date;

$sql$,
    prices_table,
    prices_table,
    period,
    period,
    prices_table,
    prices_table,
    period,
    period
);

END;
$$;
