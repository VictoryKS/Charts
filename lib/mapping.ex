defmodule Statistic.Mapping do
  alias __MODULE__
  alias Statistic.Dataset

  defstruct [:column_map, :accessors, :expected_mappings, :dataset]

  def new(expected_mappings, provided_mappings, %Dataset{} = dataset) do
    column_map = check_mappings(provided_mappings, expected_mappings, dataset)
    mapped_accessors = accessors(dataset, column_map)

    %Mapping{
      column_map: column_map,
      expected_mappings: expected_mappings,
      dataset: dataset,
      accessors: mapped_accessors
    }
  end

  defp check_mappings(nil, expected_mappings, %Dataset{} = dataset), do:
    check_mappings(default_mapping(expected_mappings, dataset), expected_mappings, dataset)
  defp check_mappings(mappings, expected_mappings, %Dataset{} = dataset), do:
    validate_mappings(optional_nil(mappings, expected_mappings), expected_mappings, dataset)

  defp default_mapping(_, %Dataset{data: [first | _]}) when is_map(first), do:
    raise(ArgumentError, "Can not create default data mappings with Map data.")
  defp default_mapping(expected_mappings, %Dataset{} = dataset) do
    Enum.with_index(expected_mappings)
    |> Enum.reduce(%{}, fn {{expected_mapping, expected_count}, index}, mapping ->
      column_name = Dataset.column_name(dataset, index)

      column_names =
        case expected_count do
          :exactly_one -> column_name
          :one_or_more -> [column_name]
          :zero_or_one -> nil
          :zero_or_more -> [nil]
        end

      Map.put(mapping, expected_mapping, column_names)
    end)
  end

  defp optional_nil(mappings, expected_mappings) do
    Enum.reduce(expected_mappings, mappings, fn {expected_mapping, expected_count}, mapping ->
      case expected_count do
        :zero_or_one ->
          if mapping[expected_mapping] == nil, do: Map.put(mapping, expected_mapping, nil), else: mapping
        :zero_or_more ->
          if mapping[expected_mapping] == nil, do: Map.put(mapping, expected_mapping, [nil]), else: mapping
        _ -> mapping
      end
    end)
  end

  defp validate_mappings(provided_mappings, expected_mappings, %Dataset{} = dataset) do
    check_required_columns!(expected_mappings, provided_mappings)
    confirm_columns_in_dataset!(dataset, provided_mappings)
    provided_mappings
  end

  defp check_required_columns!(expected_mappings, column_map) do
    required_mappings = Enum.map(expected_mappings, fn {k, _} -> k end)
    provided_mappings = Map.keys(column_map)
    missing_mappings = missing_columns(required_mappings, provided_mappings)

    case missing_mappings do
      [] -> :ok
      mappings ->
        mapping_string = Enum.map_join(mappings, ", ", &"\"#{&1}\"")
        raise "Required mapping(s) #{mapping_string} not included in column map."
    end
  end

  defp confirm_columns_in_dataset!(dataset, column_map) do
    available_columns = [nil | Dataset.column_names(dataset)]

    missing_columns =
      Map.values(column_map)
      |> List.flatten()
      |> missing_columns(available_columns)

    case missing_columns do
      [] -> :ok
      columns ->
        column_string = Enum.map_join(columns, ", ", &"\"#{&1}\"")
        raise "Column(s) #{column_string} in the column mapping not in the dataset."
    end
  end

  defp missing_columns(required_columns, provided_columns) do
    MapSet.new(required_columns)
    |> MapSet.difference(MapSet.new(provided_columns))
    |> MapSet.to_list()
  end

  defp accessors(dataset, column_map) do
    Enum.map(column_map, fn {mapping, columns} -> {mapping, accessor(dataset, columns)} end)
    |> Enum.into(%{})
  end

  defp accessor(dataset, columns) when is_list(columns), do: Enum.map(columns, &accessor(dataset, &1))
  defp accessor(_, nil), do: fn _ -> nil end
  defp accessor(dataset, column), do: Dataset.value_fn(dataset, column)
end


