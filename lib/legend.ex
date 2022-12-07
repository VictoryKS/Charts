defmodule Statistic.Legend do
  import Statistic.SVG
  alias Statistic.CategoryColourScale

  def to_svg(scale, invert \\ false) do
    values =
      case invert do
        true -> Enum.reverse(scale.values)
        _ -> scale.values
      end

    legend_items =
      Enum.with_index(values)
      |> Enum.map(fn {val, index} ->
        fill = CategoryColourScale.colour_for_value(scale, val)
        y = index * 21

        [
          rect({0, 18}, {y, y + 18}, "", fill: fill),
          text(23, y + 9, val, text_anchor: "start", dominant_baseline: "central")
        ]
      end)

    ["<g class=\"exc-legend\">", legend_items, "</g>"]
  end
end