defmodule Statistic.BarChart do
  import Statistic.SVG
  alias __MODULE__
  alias Statistic.{Scale, ContinuousLinearScale, OrdinalScale}
  alias Statistic.CategoryColourScale
  alias Statistic.{Dataset, Mapping}
  alias Statistic.Axis
  alias Statistic.Utils

  defstruct [:dataset, :mapping, :options, :category_scale, :value_scale, :series_fill_colours,
             :phx_event_handler, :value_range, :select_item]

  @required_mappings [category_col: :exactly_one, value_cols: :one_or_more]

  @default_options [
    type: :stacked,
    orientation: :vertical,
    axis_label_rotation: :auto,
    custom_value_scale: nil,
    custom_value_formatter: nil,
    width: 100,
    height: 100,
    padding: 2,
    data_labels: true,
    colour_palette: :default,
    phx_event_handler: nil,
    phx_event_target: nil,
    select_item: nil,
    colour_pattern: :category
  ]

  def new(%Dataset{} = dataset, options \\ []) do
    options = Keyword.merge(@default_options, options)
    mapping = Mapping.new(@required_mappings, Keyword.get(options, :mapping), dataset)
    %BarChart{dataset: dataset, mapping: mapping, options: options}
  end

  def set_size(%BarChart{} = plot, width, height) do
    plot
    |> set_option(:width, width)
    |> set_option(:height, height)
  end

  def get_svg_legend(%BarChart{options: options} = plot) do
    plot = prepare_scales(plot)
    scale = plot.series_fill_colours

    orientation = Keyword.get(options, :orientation)
    type = Keyword.get(options, :type)

    invert = orientation == :vertical and type == :stacked

    Statistic.Legend.to_svg(scale, invert)
  end

  def to_svg(%BarChart{options: options} = plot, plot_options) do
    plot = prepare_scales(plot)
    category_scale = plot.category_scale
    value_scale = plot.value_scale

    orientation = Keyword.get(options, :orientation)
    plot_options = refine_options(plot_options, orientation)

    category_axis = get_category_axis(category_scale, orientation, plot)

    value_axis = get_value_axis(value_scale, orientation, plot)
    plot = %{plot | value_scale: value_scale, select_item: get_option(plot, :select_item)}

    cat_axis_svg = if plot_options.show_cat_axis, do: Axis.to_svg(category_axis), else: ""

    val_axis_svg = if plot_options.show_val_axis, do: Axis.to_svg(value_axis), else: ""

    [cat_axis_svg, val_axis_svg, "<g>", get_svg_bars(plot, get_option(plot, :colour_pattern)), "</g>"]
  end

  defp refine_options(options, :horizontal) do
    options
    |> Map.put(:show_cat_axis, options.show_y_axis)
    |> Map.put(:show_val_axis, options.show_x_axis)
  end
  defp refine_options(options, _) do
    options
    |> Map.put(:show_cat_axis, options.show_x_axis)
    |> Map.put(:show_val_axis, options.show_y_axis)
  end

  defp get_category_axis(category_scale, :horizontal, plot) do
    category_scale
    |> Axis.new(:left)
    |> Axis.set_offset(get_option(plot, :width))
  end
  defp get_category_axis(category_scale, _, plot) do
    rotation =
      case get_option(plot, :axis_label_rotation) do
        :auto -> if length(Scale.ticks_range(category_scale)) > 8, do: 45, else: 0
        degrees -> degrees
      end

    category_scale
    |> Axis.new(:bottom)
    |> Axis.set_offset(get_option(plot, :height))
    |> struct(rotation: rotation)
  end

  defp get_value_axis(value_scale, :horizontal, plot) do
    value_scale
    |> Axis.new(:bottom)
    |> Axis.set_offset(get_option(plot, :height))
  end
  defp get_value_axis(value_scale, _, plot) do
    value_scale
    |> Axis.new(:left)
    |> Axis.set_offset(get_option(plot, :width))
  end

  defp get_svg_bars(%BarChart{mapping: %{column_map: column_map}, dataset: dataset} = plot, :category) do
    fills = Enum.map(column_map.value_cols, fn column -> CategoryColourScale.colour_for_value(plot.series_fill_colours, column) end)
    dataset.data |> Enum.map(fn row -> get_svg_bar(row, plot, fills) end)
  end

  defp get_svg_bars(%BarChart{mapping: %{column_map: column_map}, dataset: dataset} = plot, _) do
    cat_accessor = dataset |> Dataset.value_fn(column_map[:category_col])

    palette = dataset.data
      |> Enum.map(&cat_accessor.(&1))
      |> CategoryColourScale.new()
      |> CategoryColourScale.set_palette(get_option(plot, :colour_palette))

    dataset.data
      |> Enum.map(fn row -> get_svg_bar(row, plot, Enum.map(column_map.value_cols, fn _ -> CategoryColourScale.colour_for_value(palette, cat_accessor.(row)) end)) end)
  end

  defp get_svg_bar(row, %BarChart{mapping: mapping, category_scale: category_scale, value_scale: value_scale} = plot, fills) do
    cat_data = mapping.accessors.category_col.(row)
    series_values = Enum.map(mapping.accessors.value_cols, fn value_col -> value_col.(row) end)
    cat_band = OrdinalScale.get_band(category_scale, cat_data)
    bar_values = prepare_bar_values(series_values, value_scale, get_option(plot, :type))
    labels = Enum.map(series_values, fn val -> Scale.get_formatted_tick(value_scale, val) end)
    event_handlers = get_bar_event_handlers(plot, cat_data, series_values)
    opacities = get_bar_opacities(plot, cat_data)

    get_svg_bar_rects(cat_band, bar_values, labels, plot, fills, event_handlers, opacities)
  end

   defp prepare_bar_values(series_values, scale, :stacked) do
    {results, _} =
      Enum.reduce(series_values, {[], 0}, fn data_val, {points, last_val} ->
        end_val = data_val + last_val
        new = {Scale.domain_to_range(scale, last_val), Scale.domain_to_range(scale, end_val)}
        {[new | points], end_val}
      end)

    Enum.reverse(results)
  end
  defp prepare_bar_values(series_values, scale, :grouped) do
    {scale_min, _} = Scale.get_range(scale)

    results =
      Enum.reduce(series_values, [], fn data_val, points ->
        range_val = Scale.domain_to_range(scale, data_val)
        [{scale_min, range_val} | points]
      end)

    Enum.reverse(results)
  end

  defp get_bar_event_handlers(%BarChart{mapping: mapping} = plot, category, series_values) do
    handler = get_option(plot, :phx_event_handler)
    target = get_option(plot, :phx_event_target)

    base_opts =
      case target do
        nil -> [phx_click: handler]
        "" -> [phx_click: handler]
        _ -> [phx_click: handler, phx_target: target]
      end

    case handler do
      nil ->
        Enum.map(mapping.column_map.value_cols, fn _ -> [] end)
      "" ->
        Enum.map(mapping.column_map.value_cols, fn _ -> [] end)
      _ ->
        Enum.zip(mapping.column_map.value_cols, series_values)
        |> Enum.map(fn {col, value} ->
          Keyword.merge(base_opts, category: category, series: col, value: value)
        end)
    end
  end

  @bar_faded_opacity "0.3"
  defp get_bar_opacities(%BarChart{select_item: %{category: selected_category}, mapping: mapping}, category)
    when selected_category != category, do: Enum.map(mapping.column_map.value_cols, fn _ -> @bar_faded_opacity end)
  defp get_bar_opacities(%BarChart{select_item: %{series: selected_series}, mapping: mapping}, _) do
    Enum.map(mapping.column_map.value_cols, fn col ->
      case col == selected_series do
        true -> ""
        _ -> @bar_faded_opacity
      end
    end)
  end
  defp get_bar_opacities(%BarChart{mapping: mapping}, _), do:
    Enum.map(mapping.column_map.value_cols, fn _ -> "" end)

  defp prepare_scales(%BarChart{} = plot) do
    plot
    |> prepare_value_scale()
    |> prepare_category_scale()
    |> prepare_colour_scale()
  end

  defp get_svg_bar_rects({cat_band_min, cat_band_max} = cat_band, bar_values, labels, plot, fills, event_handlers, opacities)
    when is_number(cat_band_min) and is_number(cat_band_max) do
    count = length(bar_values)
    indices = 0..(count - 1)

    orientation = get_option(plot, :orientation)

    adjusted_bands =
      Enum.map(indices, fn index ->
        adjust_cat_band(cat_band, index, count, get_option(plot, :type), orientation)
      end)

    rects =
      Enum.zip([bar_values, fills, labels, adjusted_bands, event_handlers, opacities])
      |> Enum.map(fn {bar_value, fill, label, adjusted_band, event_opts, opacity} ->
        {x, y} = get_bar_rect_coords(orientation, adjusted_band, bar_value)
        opts = [fill: fill, opacity: opacity] ++ event_opts
        rect(x, y, title(label), opts)
      end)

    texts =
      case count < 4 and get_option(plot, :data_labels) do
        false -> []
        _ ->
          Enum.zip([bar_values, labels, adjusted_bands])
          |> Enum.map(fn {bar_value, label, adjusted_band} ->
            get_svg_bar_label(orientation, bar_value, label, adjusted_band, plot)
          end)
      end

    [rects, texts]
  end
  defp get_svg_bar_rects(_, _, _, _, _, _, _), do: ""

  defp adjust_cat_band(cat_band, _, _, :stacked, _), do: cat_band
  defp adjust_cat_band({cat_band_start, cat_band_end}, index, count, :grouped, :vertical) do
    interval = (cat_band_end - cat_band_start) / count
    {cat_band_start + index * interval, cat_band_start + (index + 1) * interval}
  end
  defp adjust_cat_band({cat_band_start, cat_band_end}, index, count, :grouped, :horizontal) do
    interval = (cat_band_end - cat_band_start) / count
    index = count - index - 1
    {cat_band_start + index * interval, cat_band_start + (index + 1) * interval}
  end

  defp get_bar_rect_coords(:horizontal, cat_band, bar_extents), do: {bar_extents, cat_band}
  defp get_bar_rect_coords(:vertical, cat_band, bar_extents), do: {cat_band, bar_extents}

  defp get_svg_bar_label(:horizontal, bar, label, cat_band, _) do
    text_y = midpoint(cat_band)
    text_x = midpoint(bar)
    text(text_x, text_y, label, text_anchor: "middle", class: "exc-barlabel-in", dominant_baseline: "central")
  end
  defp get_svg_bar_label(_, {_bar_start, bar_end} = _bar, label, cat_band, _) do
    text_x = midpoint(cat_band)
    text_y = bar_end - 3
    label = if label == "0", do: "", else: label
    text(text_x, text_y, label, text_anchor: "middle", class: "exc-barlabel-out")
  end


  defp prepare_value_scale(%BarChart{dataset: dataset, mapping: mapping} = plot) do
    val_col_names = mapping.column_map[:value_cols]
    custom_value_scale = get_option(plot, :custom_value_scale)

    val_scale =
      case custom_value_scale do
        nil ->
          {min, max} =
            get_overall_value_domain(plot, dataset, val_col_names, get_option(plot, :type))
            |> Utils.fixup_value_range()

          ContinuousLinearScale.new()
          |> ContinuousLinearScale.domain(min, max)
          |> struct(custom_tick_formatter: get_option(plot, :custom_value_formatter))
        _ -> custom_value_scale
      end

    {r_start, r_end} = get_range(:value, plot)
    val_scale = Scale.set_range(val_scale, r_start, r_end)

    %{plot | value_scale: val_scale, mapping: mapping}
  end

  defp prepare_category_scale(%BarChart{dataset: dataset, options: options, mapping: mapping} = plot) do
    padding = Keyword.get(options, :padding, 2)

    cat_col_name = mapping.column_map[:category_col]
    categories = Dataset.unique_values(dataset, cat_col_name)
    {r_min, r_max} = get_range(:category, plot)

    cat_scale =
      OrdinalScale.new(categories)
      |> Scale.set_range(r_min, r_max)
      |> OrdinalScale.padding(padding)

    %{plot | category_scale: cat_scale}
  end

  defp prepare_colour_scale(%BarChart{mapping: mapping} = plot) do
    val_col_names = mapping.column_map[:value_cols]

    series_fill_colours =
      val_col_names
      |> CategoryColourScale.new()
      |> CategoryColourScale.set_palette(get_option(plot, :colour_palette))

    %{plot | series_fill_colours: series_fill_colours, mapping: mapping}
  end

  defp get_overall_value_domain(%BarChart{value_range: {min, max}}, _, _, _), do: {min, max}
  defp get_overall_value_domain(_, dataset, col_names, :stacked) do
    {_, max} = Dataset.combined_column_extents(dataset, col_names)
    {0, max}
  end
  defp get_overall_value_domain(_, dataset, col_names, :grouped) do
    combiner = fn {min1, max1}, {min2, max2} ->
      {Utils.safe_min(min1, min2), Utils.safe_max(max1, max2)}
    end

    Enum.reduce(col_names, {nil, nil}, fn col, acc_extents ->
      inner_extents = Dataset.column_extents(dataset, col)
      combiner.(acc_extents, inner_extents)
    end)
  end

  defp get_range(:category, %BarChart{} = plot) do
    case get_option(plot, :orientation) do
      :horizontal -> {get_option(plot, :height), 0}
      _ -> {0, get_option(plot, :width)}
    end
  end
  defp get_range(:value, %BarChart{} = plot) do
    case get_option(plot, :orientation) do
      :horizontal -> {0, get_option(plot, :width)}
      _ -> {get_option(plot, :height), 0}
    end
  end

  defp set_option(%BarChart{options: options} = plot, key, value), do:
    %{plot | options: Keyword.put(options, key, value)}

  defp get_option(%BarChart{options: options}, key), do:
    Keyword.get(options, key)

  defp midpoint({a, b}), do: (a + b) / 2.0
end
