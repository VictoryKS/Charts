defmodule Statistic.Utils do

  def date_compare(%DateTime{} = a, %DateTime{} = b), do:
    DateTime.compare(a, b)
  def date_compare(%NaiveDateTime{} = a, %NaiveDateTime{} = b), do:
    NaiveDateTime.compare(a, b)

  defp date_min(a, b), do: if(date_compare(a, b) == :lt, do: a, else: b)
  defp date_max(a, b), do: if(date_compare(a, b) != :lt, do: a, else: b)

  def date_diff(%DateTime{} = a, %DateTime{} = b, unit), do: DateTime.diff(a, b, unit)
  def date_diff(%NaiveDateTime{} = a, %NaiveDateTime{} = b, unit),
    do: NaiveDateTime.diff(a, b, unit)

  def date_add(dt, amount_to_add, :years), do: shift_by(dt, amount_to_add, :years)
  def date_add(dt, amount_to_add, :months) do
    new_date = shift_by(dt, amount_to_add, :months)
    if is_last_day_of_month(dt) do
      ldom_new = :calendar.last_day_of_the_month(new_date.year, new_date.month)
      %{new_date | day: ldom_new}
    else
      new_date
    end
  end

  def date_add(%DateTime{} = dt, amount_to_add, unit), do: DateTime.add(dt, amount_to_add, unit)
  def date_add(%NaiveDateTime{} = dt, amount_to_add, unit), do: NaiveDateTime.add(dt, amount_to_add, unit)

  def safe_min(nil, nil), do: nil
  def safe_min(nil, b), do: b
  def safe_min(a, ""), do: a
  def safe_min("", b), do: b
  def safe_min(a, nil), do: a
  def safe_min(%DateTime{} = a, %DateTime{} = b), do: date_min(a, b)
  def safe_min(%NaiveDateTime{} = a, %NaiveDateTime{} = b), do: date_min(a, b)
  def safe_min(a, b) when is_number(a) and is_number(b), do: min(a, b)
  def safe_min(_, _), do: nil

  def safe_max(nil, nil), do: nil
  def safe_max(nil, b), do: b
  def safe_max(a, nil), do: a
  def safe_max("", b), do: b
  def safe_max(a, ""), do: a
  def safe_max(%DateTime{} = a, %DateTime{} = b), do: date_max(a, b)
  def safe_max(%NaiveDateTime{} = a, %NaiveDateTime{} = b), do: date_max(a, b)
  def safe_max(a, b) when is_number(a) and is_number(b), do: max(a, b)
  def safe_max(_, _), do: nil

  def safe_add(x, y), do: safe_combine(x, y, fn x, y -> x + y end)

  defp safe_combine(x, y, combiner) when is_number(x) and is_number(y), do: combiner.(x, y)
  defp safe_combine(x, _, _) when is_number(x), do: x
  defp safe_combine(_, y, _) when is_number(y), do: y
  defp safe_combine(_, _, _), do: nil

  def fixup_value_range({min, max}) when min == max and max > 0, do: {0, max}
  def fixup_value_range({min, max}) when min == max and max < 0, do: {max, 0}
  def fixup_value_range({0, 0}), do: {0, 1}
  def fixup_value_range({0.0, 0.0}), do: {0.0, 1.0}
  def fixup_value_range({min, max}), do: {min, max}
  
  defp is_last_day_of_month(%{year: year, month: month, day: day}), do: :calendar.last_day_of_the_month(year, month) == day
  
  defp shift_by(%{year: y} = datetime, value, :years) do
    shifted = %{datetime | year: y + value}
    # If a plain shift of the year fails, then it likely falls on a leap day,
    # so set the day to the last day of that month
    case :calendar.valid_date({shifted.year, shifted.month, shifted.day}) do
      false ->
        last_day = :calendar.last_day_of_the_month(shifted.year, shifted.month)
        %{shifted | day: last_day}

      true ->
        shifted
    end
  end

  defp shift_by(%{} = datetime, 0, :months), do: datetime
  # Positive shifts
  defp shift_by(%{year: year, month: month, day: day} = datetime, value, :months)
       when value > 0 do
    if month + value <= 12 do
      ldom = :calendar.last_day_of_the_month(year, month + value)

      if day > ldom do
        %{datetime | month: month + value, day: ldom}
      else
        %{datetime | month: month + value}
      end
    else
      diff = 12 - month + 1
      shift_by(%{datetime | year: year + 1, month: 1}, value - diff, :months)
    end
  end

  # Negative shifts
  defp shift_by(%{year: year, month: month, day: day} = datetime, value, :months) do
    cond do
      month + value >= 1 ->
        ldom = :calendar.last_day_of_the_month(year, month + value)

        if day > ldom do
          %{datetime | month: month + value, day: ldom}
        else
          %{datetime | month: month + value}
        end

      :else ->
        shift_by(%{datetime | year: year - 1, month: 12}, value + month, :months)
    end
  end
end
