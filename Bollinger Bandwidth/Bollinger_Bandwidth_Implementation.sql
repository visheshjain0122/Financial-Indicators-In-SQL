With Recursive 

bbwidth As (

	-- Anchor part 
	
	Select
		s.date,
		s.close,
		Array[s.close] As window_close
	From stock_prices As s
	Where s.date = (Select Min(date) From stock_prices)

	Union All

	-- Recursion Starts Here

	Select
		s.date,
		s.close,
		Case 
			When array_length(bbwidth.window_close, 1) < 10
			Then bbwidth.window_close || s.close
			Else (bbwidth.window_close[2:10] || s.close)
		End As window_close
	From bbwidth
	Join stock_prices s On s.date = (
		Select Min(date)
		From stock_prices
		Where date > bbwidth.date
	)
	
),

-- Window Calculations

bbwidth_calc As (
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
			Then (Select Stddev_Samp(x) from Unnest(window_close) As x)
		End As std
	From bbwidth
)


-- Outputting

Select 
	date,
	close,
	sma,
	std,
	sma + 2*std As upper_band,
	sma - 2*std As lower_band,
	((4*std)/SMA)*100 As bandwidth
From bbwidth_calc

Order By date;

