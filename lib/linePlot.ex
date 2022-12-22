defmodule Statistic.LinePlot do
  import Statistic.SVG
  alias __MODULE__
  alias Statistic.{Scale, ContinuousLinearScale}
  alias Statistic.CategoryColourScale
  alias Statistic.{Dataset, Mapping}
  alias Statistic.Axis
  alias Statistic.Utils

  defstruct [:dataset, :mapping, :options, :x_scale, :y_scale, :legend_scale, transforms: %{}, colour_palette: :default]

  @required_mappings [x_col: :exactly_one, y_cols: :one_or_more, fill_col: :zero_or_one]

  @default_options [axis_label_rotation: :auto, custom_x_scale: nil, custom_y_scale: nil, custom_x_formatter: nil, custom_y_formatter: nil,
                    width: 600, height: 400, smoothed: true, stroke_width: "2", colour_palette: :default]

  @default_plot_options %{show_x_axis: true, show_y_axis: true, legend_setting: :legend_none}

  def new(%Dataset{} = dataset, options \\ []) do
    options = Keyword.merge(@default_options, options)
    mapping = Mapping.new(@required_mappings, Keyword.get(options, :mapping), dataset)

    %LinePlot{dataset: dataset, mapping: mapping, options: options}
  end

  def set_size(%LinePlot{} = plot, width, height) do
    plot
    |> set_option(:width, width)
    |> set_option(:height, height)
  end

  defp set_option(%LinePlot{options: options} = plot, key, value) do
    options = Keyword.put(options, key, value)

    %{plot | options: options}
  end

  defp get_option(%LinePlot{options: options}, key), do:
    Keyword.get(options, key)

  def get_svg_legend(%LinePlot{} = plot) do
    plot = prepare_scales(plot)
    Statistic.Legend.to_svg(plot.legend_scale)
  end
  def get_svg_legend(_), do: ""

  def to_svg(%LinePlot{} = plot, plot_options) do
    plot = prepare_scales(plot)
    x_scale = plot.x_scale
    y_scale = plot.y_scale

    plot_options = Map.merge(@default_plot_options, plot_options)

    {x_axis_svg, grid_svg} =
      if plot_options.show_x_axis, do:
        (x_axis = get_x_axis(x_scale, plot)
        {Axis.to_svg(x_axis), Axis.gridlines_to_svg(x_axis)}),
      else: {"", ""}

    y_axis_svg =
      if plot_options.show_y_axis, do:
        Axis.new(y_scale, :left) |> Axis.set_offset(get_option(plot, :width)) |> Axis.to_svg(),
      else: ""

      [x_axis_svg, y_axis_svg, grid_svg, "<g>", get_svg_lines(plot), "</g>"]
  end

  defp get_x_axis(x_scale, plot) do
    rotation =
      case get_option(plot, :axis_label_rotation) do
        :auto ->
          if length(Scale.ticks_range(x_scale)) > 8, do: 45, else: 0
        degrees -> degrees
      end

    x_scale
    |> Axis.new(:bottom)
    |> Axis.set_offset(get_option(plot, :height))
    |> Kernel.struct(rotation: rotation)
  end

  defp get_svg_lines(%LinePlot{dataset: dataset, mapping: %{accessors: accessors}, transforms: transforms} = plot) do
    x_accessor = accessors.x_col

    data = Enum.sort(dataset.data, fn a, b -> x_accessor.(a) > x_accessor.(b) end)

    Enum.with_index(accessors.y_cols)
    |> Enum.map(fn {y_accessor, index} ->
      colour = transforms.colour.(index, nil)
      get_svg_line(plot, data, y_accessor, colour)
    end)
  end

  defp get_svg_line(%LinePlot{mapping: %{accessors: accessors}, transforms: transforms} = plot, data, y_accessor, colour) do
    smooth = get_option(plot, :smoothed)
    stroke_width = get_option(plot, :stroke_width)

    options = [transparent: true, stroke: colour, stroke_width: stroke_width, stroke_linejoin: "round"]
    start_point = case data do [[x, y] | _] -> [{transforms.x.(x), transforms.y.(y)}, {transforms.x.(x), transforms.y.(0)}]; _ -> [] end
    end_point = case :lists.reverse(data) do [[x, y] | _] -> [{transforms.x.(x), transforms.y.(0)}, {transforms.x.(x), transforms.y.(y)}]; _ -> [] end
    
    points_list =
      data
      |> Stream.map(fn row ->
        x =
          accessors.x_col.(row)
          |> transforms.x.()

        y =
          y_accessor.(row)
          |> transforms.y.()

        {x, y}
      end)
      |> Enum.filter(fn {x, _} -> not is_nil(x) end)
      |> Enum.sort(fn {x1, _}, {x2, _} -> x1 < x2 end)
      |> Enum.chunk_by(fn {_, y} -> is_nil(y) end)
      |> Enum.filter(fn [{_, y} | _] -> not is_nil(y) end)

    gradient("line_gradient", [{0, "lineplot-gradient-1"}, {100, "lineplot-gradient-2"}]) ++
      Enum.map(points_list, fn points -> line(points, smooth, options) end) ++
        [[{end_point, false, :first}, {:lists.flatten(points_list), smooth, :inner}, {start_point, false, :inner}]
          |> line(smooth, [class: "lineplot-fill", gradient: "line_gradient"])]
  end

  defp gradient(id, stops), do:
    ["<linearGradient id=\"#{id}\" x1=\"0\" x2=\"0\" y1=\"0\" y2=\"1\">"] ++
      :lists.map(fn {offset, class} -> "<stop offset=\"#{offset}%\", class=\"#{class}\"/>" end, stops) ++
    ["</linearGradient>"]

  def prepare_scales(%LinePlot{} = plot) do
    plot
    |> prepare_x_scale()
    |> prepare_y_scale()
    |> prepare_colour_scale()
  end

  defp prepare_x_scale(%LinePlot{dataset: dataset, mapping: mapping} = plot) do
    x_col_name = mapping.column_map[:x_col]
    width = get_option(plot, :width)
    custom_x_scale = get_option(plot, :custom_x_scale)

    x_scale =
      case custom_x_scale do
        nil -> create_scale_for_column(dataset, x_col_name, {0, width})
        _ -> custom_x_scale |> Scale.set_range(0, width)
      end

    x_scale = %{x_scale | custom_tick_formatter: get_option(plot, :custom_x_formatter)}
    x_transform = Scale.domain_to_range_fn(x_scale)
    transforms = Map.merge(plot.transforms, %{x: x_transform})

    %{plot | x_scale: x_scale, transforms: transforms}
  end

  defp prepare_y_scale(%LinePlot{dataset: dataset, mapping: mapping} = plot) do
    y_col_names = mapping.column_map[:y_cols]
    height = get_option(plot, :height)
    custom_y_scale = get_option(plot, :custom_y_scale)

    y_scale =
      case custom_y_scale do
        nil ->
          {_min, max} =
            get_overall_domain(dataset, y_col_names)
            |> Utils.fixup_value_range()

          ContinuousLinearScale.new()
          |> ContinuousLinearScale.domain(0, max)
          |> Scale.set_range(height, 0)
        _ -> custom_y_scale |> Scale.set_range(height, 0)
      end

    y_scale = %{y_scale | custom_tick_formatter: get_option(plot, :custom_y_formatter)}
    y_transform = Scale.domain_to_range_fn(y_scale)
    transforms = Map.merge(plot.transforms, %{y: y_transform})

    %{plot | y_scale: y_scale, transforms: transforms}
  end

  defp prepare_colour_scale(%LinePlot{dataset: dataset, mapping: mapping} = plot) do
    y_col_names = mapping.column_map[:y_cols]
    fill_col_name = mapping.column_map[:fill_col]
    palette = get_option(plot, :colour_palette)

    legend_scale = create_legend_colour_scale(y_col_names, fill_col_name, dataset, palette)

    transform = create_colour_transform(y_col_names, fill_col_name, dataset, palette)
    transforms = Map.merge(plot.transforms, %{colour: transform})

    %{plot | legend_scale: legend_scale, transforms: transforms}
  end

  defp create_legend_colour_scale(y_col_names, fill_col_name, dataset, palette)
    when length(y_col_names) == 1 and not is_nil(fill_col_name) do
    vals = Dataset.unique_values(dataset, fill_col_name)
    CategoryColourScale.new(vals) |> CategoryColourScale.set_palette(palette)
  end
  defp create_legend_colour_scale(y_col_names, _fill_col_name, _dataset, palette) do
    CategoryColourScale.new(y_col_names) |> CategoryColourScale.set_palette(palette)
  end

  defp create_colour_transform(y_col_names, fill_col_name, dataset, palette)
    when length(y_col_names) == 1 and not is_nil(fill_col_name) do
    vals = Dataset.unique_values(dataset, fill_col_name)
    scale = CategoryColourScale.new(vals) |> CategoryColourScale.set_palette(palette)

    fn _, fill_val -> CategoryColourScale.colour_for_value(scale, fill_val) end
  end
  defp create_colour_transform(y_col_names, _, _, palette) do
    fill_indices =
      Enum.with_index(y_col_names)
      |> Enum.map(fn {_, index} -> index end)

    scale = CategoryColourScale.new(fill_indices) |> CategoryColourScale.set_palette(palette)

    fn col_index, _ -> CategoryColourScale.colour_for_value(scale, col_index) end
  end

  defp get_overall_domain(dataset, col_names) do
    combiner = fn {min1, max1}, {min2, max2} ->
      {Utils.safe_min(min1, min2), Utils.safe_max(max1, max2)}
    end

    Enum.reduce(col_names, {nil, nil}, fn col, acc_extents ->
      inner_extents = Dataset.column_extents(dataset, col)
      combiner.(acc_extents, inner_extents)
    end)
  end

  defp create_scale_for_column(dataset, column, {r_min, r_max}) do
    {min, max} = Dataset.column_extents(dataset, column)

    ContinuousLinearScale.new()
    |> ContinuousLinearScale.domain(min, max)
    |> Scale.set_range(r_min, r_max)
  end
end
