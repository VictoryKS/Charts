defmodule Statistic.Dataset do
  alias __MODULE__
  alias Statistic.Utils

  defstruct [:headers, :data, :title, :meta]

  def new(data), do: %Dataset{headers: nil, data: data}
  def new(data, headers), do: %Dataset{headers: headers, data: data}

  def column_index(%Dataset{data: [first | _]}, name) when is_map(first) do
    if Map.has_key?(first, name) do name else nil end end
  def column_index(%Dataset{headers: h}, name) when is_list(h), do:
    Enum.find_index(h, fn col -> col == name end)
  def column_index(_, name) when is_integer(name), do: name
  def column_index(_, _), do: nil

  def column_names(%Dataset{headers: h}) when not is_nil(h), do: h
  def column_names(%Dataset{data: [first | _]}) when is_map(first), do: Map.keys(first)
  def column_names(%Dataset{data: [first | _]}) when is_tuple(first) do
    max = tuple_size(first) - 1
    0..max |> Enum.into([])
  end
  def column_names(%Dataset{data: [first | _]}) when is_list(first) do
    max = length(first) - 1
    0..max |> Enum.into([])
  end
  def column_names(%Dataset{headers: h}), do: h

  def column_name(%Dataset{headers: h}, index) when is_list(h)
                                               and is_integer(index)
                                               and index < length(h), do: Enum.at(h, index)
  def column_name(_, index), do: index

  def value_fn(%Dataset{data: [first | _]}, name) when is_map(first) and is_binary(name), do:
    fn row -> row[name] end
  def value_fn(%Dataset{data: [first | _]}, name) when is_map(first) and is_atom(name), do:
    fn row -> row[name] end
  def value_fn(%Dataset{data: [first | _]} = dataset, name) when is_list(first), do:
    fn row -> Enum.at(row, column_index(dataset, name), nil) end
  def value_fn(%Dataset{data: [first | _]} = dataset, name) when is_tuple(first) do
    index = column_index(dataset, name)
    if index < tuple_size(first) do
      fn row -> elem(row, index) end
    else
      fn _ -> nil end
    end
  end

  def value_fn(_dataset, _column_name), do: fn _ -> nil end

  def column_extents(%Dataset{data: data} = dataset, column_name) do
    accessor = value_fn(dataset, column_name)

    Enum.reduce(data, {nil, nil}, fn row, {min, max} ->
      val = accessor.(row)
      {Utils.safe_min(val, min), Utils.safe_max(val, max)}
    end)
  end

  def combined_column_extents(%Dataset{data: data} = dataset, column_names) do
    accessors =
      Enum.map(column_names, fn column_name -> value_fn(dataset, column_name) end)

    Enum.reduce(data, {nil, nil}, fn row, {min, max} ->
      val = sum_row_values(row, accessors)
      {Utils.safe_min(val, min), Utils.safe_max(val, max)}
    end)
  end

  defp sum_row_values(row, accessors) do
    Enum.reduce(accessors, 0, fn accessor, acc ->
      val = accessor.(row)
      Utils.safe_add(acc, val)
    end)
  end

  def unique_values(%Dataset{data: data} = dataset, column_name) do
    accessor = value_fn(dataset, column_name)

    {result, _} =
      Enum.reduce(data, {[], MapSet.new()}, fn row, {result, found} ->
        val = accessor.(row)

        case MapSet.member?(found, val) do
          true -> {result, found}
          _ -> {[val | result], MapSet.put(found, val)}
        end
      end)

    Enum.reverse(result)
  end
end
