With Recursive

EMA_Tab As (

	-- Anchor Part

	Select 
		s.date,
		s.close,
		Array[s.close] As window_close
	From stock_prices As s
	Where s.date = (Select Min(date) From stock_prices)

	Union All

	-- Recursion CTE

	Select 
		s.date,
		s.close,
		Case
			When array_length(EMA_Tab.window_close, 1) < 10
			Then EMA_Tab.window_close || s.close
			Else (EMA_Tab.window_close[2:10] || s.close)
		End As window_close
	From EMA_Tab
	Join stock_prices s On s.date = (
		Select Min(date)
		From stock_prices
		Where date > EMA_Tab.date
	)
),


-- Window Calc

EMA_calc As (
	Select 
		date, 
		close,
		window_close,
		Case
			When array_length(window_close, 1) = 10
			Then (Select Avg(x) From Unnest(window_close) As x)
		End As sma,
		Case
			When array_length(window_close, 1) = 10
			Then (2.0/(10+1))
		End As smooth_const
	From EMA_Tab
)

-- Outputting

Select 
	date,
	close,
	sma,
	smooth_const,
	sma * smooth_const As EMA
From EMA_calc

Order By date;