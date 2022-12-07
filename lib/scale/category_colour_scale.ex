defmodule Statistic.CategoryColourScale do
  alias __MODULE__

  defstruct [:values, :colour_palette, :colour_map, :default_colour]

  def new(raw_values, palette \\ :default) when is_list(raw_values) do
    values = Enum.uniq(raw_values)

    %CategoryColourScale{values: values}
    |> set_palette(palette)
  end

  def set_palette(%CategoryColourScale{} = colour_scale, nil), do:
    set_palette(colour_scale, :default)
  def set_palette(%CategoryColourScale{} = colour_scale, palette) when is_atom(palette), do:
    set_palette(colour_scale, get_palette(palette))
  def set_palette(%CategoryColourScale{} = colour_scale, palette) when is_list(palette) do
    %{colour_scale | colour_palette: palette}
    |> map_values_to_palette()
  end

  defp map_values_to_palette(%CategoryColourScale{values: values, colour_palette: palette} = colour_scale) do
    {_, colour_map} =
      Enum.reduce(values, {0, Map.new()}, fn value, {index, current_result} ->
        colour = get_colour(palette, index)
        {index + 1, Map.put(current_result, value, colour)}
      end)

    %{colour_scale | colour_map: colour_map}
  end

  @default_palette ["1f77b4", "ff7f0e", "2ca02c", "d62728", "9467bd", "8c564b", "e377c2", "7f7f7f", "bcbd22", "17becf"]
  @pastel1_palette ["fbb4ae", "b3cde3", "ccebc5", "decbe4", "fed9a6", "ffffcc", "e5d8bd", "fddaec", "f2f2f2"]
  @warm_palette ["d40810", "e76241", "f69877", "ffcab4", "ffeac4", "fffae4"]
  defp get_palette(:default), do: @default_palette
  defp get_palette(:pastel1), do: @pastel1_palette
  defp get_palette(:warm), do: @warm_palette
  defp get_palette(_), do: nil

  defp get_colour(colour_palette, index) when is_list(colour_palette) do
    palette_length = length(colour_palette)
    adjusted_index = rem(index, palette_length)
    Enum.at(colour_palette, adjusted_index)
  end

  @default_colour "fa8866"
  def colour_for_value(nil, _value), do: @default_colour
  def colour_for_value(%CategoryColourScale{colour_map: colour_map} = colour_scale, value) do
    case Map.fetch(colour_map, value) do
      {:ok, result} -> result
      _ -> get_default_colour(colour_scale)
    end
  end

  def get_default_colour(%CategoryColourScale{default_colour: default}) when is_binary(default), do: default
  def get_default_colour(_), do: @default_colour
end
