defmodule SocialScribe.SalesforceSuggestions do
  @moduledoc """
  Generates and formats Salesforce contact update suggestions by combining
  AI-extracted data with existing Salesforce contact information.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.SalesforceApi
  alias SocialScribe.Accounts.UserCredential

  @field_labels %{
    "FirstName" => "First Name",
    "LastName" => "Last Name",
    "Email" => "Email",
    "Phone" => "Phone",
    "MobilePhone" => "Mobile Phone",
    "Title" => "Title",
    "MailingStreet" => "Mailing Street",
    "MailingCity" => "City",
    "MailingState" => "State",
    "MailingPostalCode" => "Postal Code",
    "MailingCountry" => "Country"
  }

  @doc """
  Generates suggested updates for a Salesforce contact based on a meeting transcript.
  """
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
    with {:ok, contact} <- SalesforceApi.get_contact(credential, contact_id),
         {:ok, ai_suggestions} <- AIContentGeneratorApi.generate_salesforce_suggestions(meeting) do
      suggestions =
        ai_suggestions
        |> Enum.map(fn suggestion ->
          field = suggestion.field
          current_value = get_contact_field(contact, field)

          %{
            field: field,
            label: Map.get(@field_labels, field, field),
            current_value: current_value,
            new_value: suggestion.value,
            context: suggestion.context,
            timestamp: suggestion[:timestamp],
            apply: true,
            has_change: current_value != suggestion.value
          }
        end)
        |> Enum.filter(fn s -> s.has_change end)

      {:ok, %{contact: contact, suggestions: suggestions}}
    end
  end

  @doc """
  Generates suggestions without fetching contact data.
  """
  def generate_suggestions_from_meeting(meeting) do
    case AIContentGeneratorApi.generate_salesforce_suggestions(meeting) do
      {:ok, ai_suggestions} ->
        suggestions =
          ai_suggestions
          |> Enum.map(fn suggestion ->
            %{
              field: suggestion.field,
              label: Map.get(@field_labels, suggestion.field, suggestion.field),
              current_value: nil,
              new_value: suggestion.value,
              context: Map.get(suggestion, :context),
              timestamp: Map.get(suggestion, :timestamp),
              apply: true,
              has_change: true
            }
          end)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Merges AI suggestions with contact data to show current vs suggested values.
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    Enum.map(suggestions, fn suggestion ->
      current_value = get_contact_field(contact, suggestion.field)

      %{suggestion | current_value: current_value, has_change: current_value != suggestion.new_value, apply: true}
    end)
    |> Enum.filter(fn s -> s.has_change end)
  end

  defp get_contact_field(contact, field) when is_map(contact) do
    # Contact has both atom keys (firstname, lastname) and Salesforce keys (FirstName, LastName)
    atom_key = if is_binary(field), do: String.to_existing_atom(field), else: field
    Map.get(contact, atom_key) || Map.get(contact, field)
  rescue
    ArgumentError -> Map.get(contact, field)
  end

  defp get_contact_field(_, _), do: nil
end
