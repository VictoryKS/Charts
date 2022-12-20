defmodule Statistic.PieChart do
  alias __MODULE__
  alias Statistic.CategoryColourScale
  alias Statistic.{Dataset, Mapping}

  defstruct [:dataset, :mapping, :options, :colour_scale]

  @required_mappings [category_col: :zero_or_one, value_col: :zero_or_one]

  @default_options [width: 600, height: 400, colour_palette: :default, colour_scale: nil, data_labels: true, inner_text: []]

  def new(%Dataset{} = dataset, options \\ []) do
    options = check_options(options)
    options = Keyword.merge(@default_options, options)
    mapping = Mapping.new(@required_mappings, Keyword.get(options, :mapping), dataset)

    %PieChart{
      dataset: dataset,
      mapping: mapping,
      options: options,
      colour_scale: Keyword.get(options, :colour_scale)
    }
  end

  defp check_options(options) do
    colour_scale = check_colour_scale(Keyword.get(options, :colour_scale))
    Keyword.put(options, :colour_scale, colour_scale)
  end

  defp check_colour_scale(%CategoryColourScale{} = scale), do: scale
  defp check_colour_scale(_), do: nil

  def set_size(%PieChart{} = chart, width, height) do
    chart
    |> set_option(:width, width)
    |> set_option(:height, height)
  end

  def get_svg_legend(%PieChart{} = chart) do
    get_colour_palette(chart)
    |> Statistic.Legend.to_svg()
  end

  def to_svg(%PieChart{} = chart, _), do: ["<g>", generate_slices(chart), "</g>"]

  defp set_option(%PieChart{options: options} = plot, key, value), do:
    %{plot | options: Keyword.put(options, key, value)}

  defp get_option(%PieChart{options: options}, key), do:
    Keyword.get(options, key)

  defp get_colour_palette(%PieChart{colour_scale: colour_scale}) when not is_nil(colour_scale), do: colour_scale
  defp get_colour_palette(%PieChart{} = chart) do
    get_categories(chart)
    |> CategoryColourScale.new()
    |> CategoryColourScale.set_palette(get_option(chart, :colour_palette))
  end

  def get_categories(%PieChart{dataset: dataset, mapping: mapping}) do
    cat_accessor = dataset |> Dataset.value_fn(mapping.column_map[:category_col])

    dataset.data
    |> Enum.map(&cat_accessor.(&1))
  end

  defp generate_slices(%PieChart{} = chart) do
    height = get_option(chart, :height)
    with_labels? = get_option(chart, :data_labels)
    colour_palette = get_colour_palette(chart)
    inner_text = get_option(chart, :inner_text)

    r = height / 2
    stroke_circumference = 2 * :math.pi() * r / 2

    inner_circle =
      case inner_text do
        [] -> []
        x ->
          ["<circle r=\"#{r / 6}\" cx=\"#{r}\" cy=\"#{r}\" fill=\"transparent\" " <>
            "stroke=\"white\" " <>
            "stroke-width=\"#{2 * r / 3}\">" <>
           "</circle>" <>
           "<text x=\"#{r}\" y=\"#{r}\" " <>
             "text-anchor=\"middle\" " <>
             "fill=\"black\" " <>
             "class=\"piechart-inner\" " <>
             "stroke-width=\"1\" " <>
           ">#{inner_text(x, r, r / 3)}</text>"]
      end

    scale_values(chart)
    |> Enum.map_reduce({0, 0}, fn {value, category, data}, {idx, offset} ->
      text_rotation = rotate_for(value, offset)

      label =
        if with_labels? do
          "<text x=\"#{negate_if_flipped(r, text_rotation)}\" " <>
            "y=\"#{negate_if_flipped(r, text_rotation)}\" " <>
            "text-anchor=\"middle\" " <>
            "fill=\"white\" " <>
            "class=\"piechart-label\" " <>
            "stroke-width=\"1\" " <>
            "transform=\"rotate(#{text_rotation}, #{r}, #{r}) " <>
              "translate(#{3 * r / 4}, #{negate_if_flipped(5, text_rotation)}) " <>
              "#{if need_flip?(text_rotation), do: "scale(-1,-1)"}\">" <>
          "#{data}</text>"
        else
          ""
        end

      {
        "<circle r=\"#{r / 2}\" cx=\"#{r}\" cy=\"#{r}\" fill=\"transparent\"" <>
          "stroke=\"##{CategoryColourScale.colour_for_value(colour_palette, category)}\"" <>
          "stroke-width=\"#{r}\"" <>
          "stroke-dasharray=\"#{slice_value(value, stroke_circumference)} #{stroke_circumference}\"" <>
          "stroke-dashoffset=\"-#{slice_value(offset, stroke_circumference)}\">" <>
        "<title>#{data}</title></circle>#{label}",
        {idx + 1, offset + value}
      }
    end)
    |> elem(0)
    |> Enum.concat(inner_circle)
    |> Enum.join()
  end

  defp inner_text(text, _r, _) when is_binary(text), do: text
  defp inner_text(text, r, slice) do
    n = length(text) - 1
    Enum.reduce(text, {"", 0.0},
      fn {t, class}, {acc, count} -> {acc <> "<tspan x=\"#{r}\" y=\"#{inner_y(count, n / 2, r, slice / n)}\" class=\"#{class}\">#{t}</tspan>", count + 1.0}
         t, {acc, count} when is_binary(t) -> {acc <> "<tspan x=\"#{r}\" y=\"#{inner_y(count, n / 2, r, slice / n)}\">#{t}</tspan>", count + 1.0}
         _, acc -> acc
      end) |> elem(0)
  end
  
  defp inner_y(count, count, r, _slice), do: r
  defp inner_y(count, n, r, slice) when count < n, do: r - slice * (count + 1)
  defp inner_y(count, n, r, slice) when count > n, do: r + slice * (count + 1 - n * 2)
      
  defp slice_value(value, stroke_circumference), do: value * stroke_circumference / 100

  defp rotate_for(n, offset), do: n / 2 * 3.6 + offset * 3.6

  defp need_flip?(rotation), do: 90 < rotation and rotation < 270

  defp negate_if_flipped(number, rotation) do
    if need_flip?(rotation),
      do: -number,
      else: number
  end

  defp scale_values(%PieChart{dataset: dataset, mapping: mapping}) do
    val_accessor = dataset |> Dataset.value_fn(mapping.column_map[:value_col])
    cat_accessor = dataset |> Dataset.value_fn(mapping.column_map[:category_col])

    sum = dataset.data |> Enum.reduce(0, fn col, acc -> val_accessor.(col) + acc end)

    dataset.data
    |> Enum.map_reduce(sum, &{{val_accessor.(&1) / &2 * 100, cat_accessor.(&1), val_accessor.(&1)}, &2})
    |> elem(0)
  end
end
