defmodule Statistic.Axis do
  alias __MODULE__
  alias Statistic.Scale

  defstruct [:scale, :orientation, rotation: 0, tick_size_inner: 6, tick_size_outer: 6, tick_padding: 3, flip_factor: 1, offset: 0]

  @orientations [:top, :left, :right, :bottom]

  def new(scale, orientation) when orientation in @orientations do
    if is_nil(Statistic.Scale.impl_for(scale)) do
      raise ArgumentError, message: "Scale must implement Statistic.Scale protocol"
    end

    %Axis{scale: scale, orientation: orientation}
  end

  def set_offset(%Axis{} = axis, offset), do: %{axis | offset: offset}

  def to_svg(%Axis{scale: scale} = axis) do
    axis = %{axis | flip_factor: get_flip_factor(axis.orientation)}
    {range0, range1} = get_adjusted_range(scale)

    [
      "<g ",
      get_svg_axis_location(axis),
      " fill=\"none\" font-size=\"10\" text-anchor=\"#{get_text_anchor(axis)}\">",
      "<path class=\"exc-domain\" stroke=\"#000\" d=\"#{get_svg_axis_line(axis, range0, range1)}\"></path>",
      get_svg_tickmarks(axis),
      "</g>"
    ]
  end

  defp get_svg_axis_location(%Axis{orientation: :bottom, offset: offset}), do:
    "transform=\"translate(0, #{offset})\""
  defp get_svg_axis_location(%Axis{orientation: :right, offset: offset}), do:
    "transform=\"translate(#{offset}, 0)\""
  defp get_svg_axis_location(_), do: " "

  defp get_text_anchor(%Axis{orientation: :right}), do: "start"
  defp get_text_anchor(%Axis{orientation: :left}), do: "end"
  defp get_text_anchor(_), do: "middle"

  defp get_svg_axis_line(%Axis{orientation: orientation} = axis, range0, range1) when orientation in [:right, :left] do
    %Axis{tick_size_outer: tick_size_outer, flip_factor: k} = axis
    "M#{k * tick_size_outer},#{range0}H0.5V#{range1}H#{k * tick_size_outer}"
  end
  defp get_svg_axis_line(%Axis{orientation: orientation} = axis, range0, range1) when orientation in [:top, :bottom] do
    %Axis{tick_size_outer: tick_size_outer, flip_factor: k} = axis
    "M#{range0}, #{k * tick_size_outer}V0.5H#{range1}V#{k * tick_size_outer}"
  end

  defp get_svg_tickmarks(%Axis{scale: scale} = axis) do
    domain_ticks = Scale.ticks_domain(scale)
    domain_to_range_fn = Scale.domain_to_range_fn(scale)

    domain_ticks
    |> Enum.map(fn tick -> get_svg_tick(axis, tick, domain_to_range_fn.(tick)) end)
  end

  defp get_svg_tick(%Axis{orientation: orientation} = axis, tick, range_tick) do
    [
      "<g class=\"exc-tick\" opacity=\"1\" transform=",
      get_svg_tick_transform(orientation, range_tick),
      ">",
      get_svg_tick_line(axis),
      get_svg_tick_label(axis, tick),
      "</g>"
    ]
  end

  defp get_svg_tick_transform(orientation, range_tick) when orientation in [:top, :bottom], do:
    "\"translate(#{range_tick + 0.5},0)\""
  defp get_svg_tick_transform(orientation, range_tick) when orientation in [:left, :right], do:
    "\"translate(0, #{range_tick + 0.5})\""

  defp get_svg_tick_line(%Axis{flip_factor: k, tick_size_inner: size} = axis) do
    dim = get_tick_dimension(axis)
    "<line #{dim}2=\"#{k * size}\"></line>"
  end

  defp get_svg_tick_label(%Axis{flip_factor: k, scale: scale} = axis, tick) do
    offset = axis.tick_size_inner + axis.tick_padding
    dim = get_tick_dimension(axis)
    text_adjust = get_svg_tick_text_adjust(axis)

    tick =
      Scale.get_formatted_tick(scale, tick)
      |> Statistic.SVG.clean()

    "<text #{dim}=\"#{k * offset}\" #{text_adjust}>#{tick}</text>"
  end

  defp get_tick_dimension(%Axis{orientation: orientation}) when orientation in [:top, :bottom], do: "y"
  defp get_tick_dimension(%Axis{orientation: orientation}) when orientation in [:left, :right], do: "x"

  defp get_svg_tick_text_adjust(%Axis{orientation: orientation}) when orientation in [:left, :right], do:
    "dy=\"0.32em\""
  defp get_svg_tick_text_adjust(%Axis{orientation: :top}), do: ""
  defp get_svg_tick_text_adjust(%Axis{orientation: :bottom, rotation: 45}), do:
    "dy=\"-0.1em\" dx=\"-0.9em\" text-anchor=\"end\" transform=\"rotate(-45)\""
  defp get_svg_tick_text_adjust(%Axis{orientation: :bottom, rotation: 90}), do:
    "dy=\"-0.51em\" dx=\"-0.9em\" text-anchor=\"end\" transform=\"rotate(-90)\""
  defp get_svg_tick_text_adjust(%Axis{orientation: :bottom}), do:
    "dy=\"0.71em\" dx=\"0\" text-anchor=\"middle\""

  defp get_flip_factor(orientation) when orientation in [:top, :left], do: -1
  defp get_flip_factor(orientation) when orientation in [:right, :bottom], do: 1

  defp get_adjusted_range(scale) do
    {min_r, max_r} = Scale.get_range(scale)
    {min_r + 0.5, max_r + 0.5}
  end
end
