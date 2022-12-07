defmodule Statistic.ContinuousLinearScale do
  alias __MODULE__
  alias Statistic.Utils

  defstruct [:domain, :nice_domain, :range, :interval_count, :interval_size, :display_decimals, :custom_tick_formatter]

  def new(), do:
    %ContinuousLinearScale{range: {0.0, 1.0}, interval_count: 10, display_decimals: nil}

  def domain(%ContinuousLinearScale{} = scale, min, max) when is_number(min) and is_number(max) do
    {d_min, d_max} =
      case min < max do
        true -> {min, max}
        _ -> {max, min}
      end

    scale
    |> struct(domain: {d_min, d_max})
    |> nice()
  end

  def domain(%ContinuousLinearScale{} = scale, data) when is_list(data) do
    {min, max} = extents(data)
    domain(scale, min, max)
  end

  defp nice(%ContinuousLinearScale{domain: {min_d, max_d}, interval_count: interval_count} = scale)
    when is_number(min_d) and is_number(max_d) and is_number(interval_count) and interval_count > 1 do
    width = max_d - min_d
    width = if width == 0.0, do: 1.0, else: width
    unrounded_interval_size = width / interval_count
    order_of_magnitude = :math.ceil(:math.log10(unrounded_interval_size) - 1)
    power_of_ten = :math.pow(10, order_of_magnitude)

    rounded_interval_size = lookup_axis_interval(unrounded_interval_size / power_of_ten) * power_of_ten

    min_nice = rounded_interval_size * Float.floor(min_d / rounded_interval_size)
    max_nice = rounded_interval_size * Float.ceil(max_d / rounded_interval_size)
    adjusted_interval_count = round(1.0001 * (max_nice - min_nice) / rounded_interval_size)

    display_decimals = guess_display_decimals(order_of_magnitude)

    %{
      scale
      | nice_domain: {min_nice, max_nice},
        interval_size: rounded_interval_size,
        interval_count: adjusted_interval_count,
        display_decimals: display_decimals
    }
  end
  defp nice(%ContinuousLinearScale{} = scale), do: scale

  def get_domain_to_range_function(%ContinuousLinearScale{nice_domain: {min_d, max_d}, range: {min_r, max_r}})
    when is_number(min_d) and is_number(max_d) and is_number(min_r) and is_number(max_r) do
    domain_width = max_d - min_d
    range_width = max_r - min_r

    case domain_width do
      0 -> fn x -> x end
      0.0 -> fn x -> x end
      _ ->
        fn domain_val ->
          case domain_val do
            nil -> nil
            _ ->
              ratio = (domain_val - min_d) / domain_width
              min_r + ratio * range_width
          end
        end
    end
  end
  def get_domain_to_range_function(_), do: fn x -> x end

  @axis_interval_breaks [0.05, 0.1, 0.2, 0.25, 0.4, 0.5, 1.0, 2.0, 2.5, 4.0, 5.0, 10.0, 20.0]
  defp lookup_axis_interval(raw_interval) when is_float(raw_interval), do:
    Enum.find(@axis_interval_breaks, fn x -> x >= raw_interval end)

  defp guess_display_decimals(power_of_ten) when power_of_ten > 0, do: 0
  defp guess_display_decimals(power_of_ten), do: 1 + -1 * round(power_of_ten)

  def extents(data), do:
    Enum.reduce(data, {nil, nil}, fn x, {min, max} -> {Utils.safe_min(x, min), Utils.safe_max(x, max)} end)

  defimpl Statistic.Scale do
    def domain_to_range_fn(%ContinuousLinearScale{} = scale), do:
      ContinuousLinearScale.get_domain_to_range_function(scale)

    def ticks_domain(%ContinuousLinearScale{nice_domain: {min_d, _}, interval_count: interval_count, interval_size: interval_size})
      when is_number(min_d) and is_number(interval_count) and is_number(interval_size) do
      0..interval_count
      |> Enum.map(fn i -> min_d + i * interval_size end)
    end
    def ticks_domain(_), do: []

    def ticks_range(%ContinuousLinearScale{} = scale) do
      transform_func = ContinuousLinearScale.get_domain_to_range_function(scale)

      ticks_domain(scale)
      |> Enum.map(transform_func)
    end

    def domain_to_range(%ContinuousLinearScale{} = scale, range_val) do
      transform_func = ContinuousLinearScale.get_domain_to_range_function(scale)
      transform_func.(range_val)
    end

    def get_range(%ContinuousLinearScale{range: {min_r, max_r}}), do: {min_r, max_r}

    def set_range(%ContinuousLinearScale{} = scale, start, finish) when is_number(start) and is_number(finish), do:
      %{scale | range: {start, finish}}
    def set_range(%ContinuousLinearScale{} = scale, {start, finish}) when is_number(start) and is_number(finish), do:
      set_range(scale, start, finish)

    def get_formatted_tick(%ContinuousLinearScale{display_decimals: display_decimals, custom_tick_formatter: custom_tick_formatter}, tick_val), do:
      format_tick_text(tick_val, display_decimals, custom_tick_formatter)

    defp format_tick_text(tick, _, custom_tick_formatter) when is_function(custom_tick_formatter), do:
      custom_tick_formatter.(tick)
    defp format_tick_text(tick, _, _) when is_integer(tick), do: to_string(tick)
    defp format_tick_text(tick, display_decimals, _) when display_decimals > 0, do:
      :erlang.float_to_binary(tick, decimals: display_decimals)
    defp format_tick_text(tick, _, _), do: :erlang.float_to_binary(tick, [:compact, decimals: 0])
  end
end
