defmodule Statistic.Plot do
  import Statistic.SVG
  alias __MODULE__
  alias Statistic.Dataset

  defstruct [:module, :title, :subtitle, :x_label, :y_label, :height, :width,
             :plot_content, :margins, :plot_options, default_style: true]

  @default_plot_options [show_x_axis: true, show_y_axis: true, legend_setting: :legend_none]

  @default_style "<style type=\"text/css\"><![CDATA[text {fill: black} line {stroke: black}]]></style>"

  @default_width 600
  @default_height 400
  @legend_width 100
  @default_padding 10
  @top_title_margin 20
  @top_subtitle_margin 15
  @y_axis_margin 20
  @y_axis_tick_labels 70
  @x_axis_margin 20
  @x_axis_tick_labels 70

  def new(%Dataset{} = dataset, module, attrs \\ []) do
    plot_content = apply(module, :new, [dataset, attrs])
    attributes = parse_attributes(Keyword.merge(@default_plot_options, attrs))

    %Plot{
      module: module,
      title: attributes.title,
      subtitle: attributes.subtitle,
      x_label: attributes.x_label,
      y_label: attributes.y_label,
      width: attributes.width,
      height: attributes.height,
      plot_content: plot_content,
      plot_options: attributes.plot_options
    }
    |> calculate_margins()
  end

  def to_svg(%Plot{module: module, width: width, height: height, plot_content: plot_content} = plot) do
    %{left: left, right: right, top: top, bottom: bottom} = plot.margins
    content_height = height - (top + bottom)
    content_width = width - (left + right)

    legend_left = left + content_width + @default_padding
    legend_top = top + @default_padding

    plot_content = apply(module, :set_size, [plot_content, content_width, content_height])

    output = [
      "<svg version=\"1.1\" xmlns=\"http://www.w3.org/2000/svg\"",
      "xmlns:xlink=\"http://www.w3.org/1999/xlink\" class=\"chart\"",
      "viewBox=\"0 0 #{width} #{height}\" role=\"img\">",
      get_default_style(plot),
      get_titles_svg(plot, content_width),
      get_axis_labels_svg(plot, content_width, content_height),
      "<g transform=\"translate(#{left}, #{top})\">",
      apply(module, :to_svg, [plot_content, plot.plot_options]),
      "</g>",
      get_svg_legend(module, plot_content, legend_left, legend_top, plot.plot_options),
      "</svg>"
    ]

    {:safe, output}
  end

  defp get_default_style(%Plot{default_style: true}), do: @default_style
  defp get_default_style(_), do: ""

  defp get_svg_legend(module, plot_content, legend_left, legend_top, %{legend_setting: :legend_right}) do
    [
      "<g transform=\"translate(#{legend_left}, #{legend_top})\">",
      apply(module, :get_svg_legend, [plot_content]),
      "</g>"
    ]
  end
  defp get_svg_legend(_, _, _, _, _), do: ""

  defp get_titles_svg(%Plot{title: title, subtitle: subtitle, margins: margins}, content_width)
    when is_binary(title) or is_binary(subtitle) do
    centre = margins.left + content_width / 2.0

    title_y = @top_title_margin

    title_svg =
      case empty(title) do
        true -> text(centre, title_y, title, class: "exc-title", text_anchor: "middle")
        _ -> ""
      end

    subtitle_y =
      case empty(title) do
        true -> @top_subtitle_margin + @top_title_margin
        _ -> @top_subtitle_margin
      end

    subtitle_svg =
      case empty(subtitle) do
        true -> text(centre, subtitle_y, subtitle, class: "exc-subtitle", text_anchor: "middle")
        _ -> ""
      end

    [title_svg, subtitle_svg]
  end
  defp get_titles_svg(_, _), do: ""

  defp get_axis_labels_svg(%Plot{x_label: x_label, y_label: y_label, margins: margins}, content_width, content_height)
    when is_binary(x_label) or is_binary(y_label) do
    x_label_x = margins.left + content_width / 2.0
    x_label_y = margins.top + content_height + @x_axis_tick_labels

    y_label_x = -1.0 * (margins.top + content_height / 2.0)
    y_label_y = @y_axis_margin

    x_label_svg =
      case empty(x_label) do
        true -> text(x_label_x, x_label_y, x_label, class: "exc-subtitle", text_anchor: "middle")
        _ -> ""
      end

    y_label_svg =
      case empty(y_label) do
        true -> text(y_label_x, y_label_y, y_label, class: "exc-subtitle", text_anchor: "middle", transform: "rotate(-90)")
        false -> ""
      end

    [x_label_svg, y_label_svg]
  end
  defp get_axis_labels_svg(_, _, _), do: ""

  defp parse_attributes(attrs) do
    %{
      title: Keyword.get(attrs, :title),
      subtitle: Keyword.get(attrs, :subtitle),
      x_label: Keyword.get(attrs, :x_label),
      y_label: Keyword.get(attrs, :y_label),
      width: Keyword.get(attrs, :width, @default_width),
      height: Keyword.get(attrs, :height, @default_height),
      plot_options: Enum.into(Keyword.take(attrs, [:show_x_axis, :show_y_axis, :legend_setting]), %{})
    }
  end

  defp calculate_margins(%Plot{} = plot) do
    left = Map.get(plot.plot_options, :left_margin, margin(:left, plot))
    top = Map.get(plot.plot_options, :top_margin, margin(:top, plot))
    right = Map.get(plot.plot_options, :right_margin, margin(:right, plot))
    bottom = Map.get(plot.plot_options, :bottom_margin, margin(:bottom, plot))

    %{plot | margins: %{left: left, top: top, right: right, bottom: bottom}}
  end

  defp margin(:left, %Plot{} = plot) do
    if plot.plot_options.show_y_axis do @y_axis_tick_labels else 0 end + if empty(plot.y_label) do @y_axis_margin else 0 end end
  defp margin(:right, %Plot{} = plot) do
    @default_padding + if plot.plot_options.legend_setting == :legend_right do @legend_width else 0 end end
  defp margin(:bottom, %Plot{} = plot) do
    if plot.plot_options.show_x_axis do @x_axis_tick_labels else 0 end + if empty(plot.x_label) do @x_axis_margin else 0 end end
  defp margin(:top, %Plot{} = plot) do
    @default_padding + if empty(plot.title) do @top_title_margin + @default_padding else 0 end + if empty(plot.subtitle) do @top_subtitle_margin else 0 end end
  defp margin(_, _), do: 0

  defp empty(val) when is_nil(val), do: false
  defp empty(val) when val == "", do: false
  defp empty(val) when is_binary(val), do: true
  defp empty(_), do: false
end