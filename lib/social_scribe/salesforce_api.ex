defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce CRM API client for Contact operations.
  Uses instance_url from credential for base URL. Implements token refresh on 401.
  """

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @contact_fields ~w(FirstName LastName Email Phone MobilePhone Title MailingStreet MailingCity MailingState MailingPostalCode MailingCountry AccountId PhotoUrl)

  defp base_url(%UserCredential{instance_url: url}) when is_binary(url) and url != "" do
    String.trim_trailing(url, "/")
  end

  defp base_url(_), do: "https://login.salesforce.com"

  defp client(credential) do
    base = base_url(credential)

    Tesla.client([
      {Tesla.Middleware.BaseUrl, base},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers,
       [
         {"Authorization", "Bearer #{credential.token}"},
         {"Content-Type", "application/json"}
       ]}
    ])
  end

  @doc """
  Searches for contacts by query string (Name, Email).
  Returns up to 10 matching contacts. Uses SOQL on Contact.
  """
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      # Escape SOQL: \ -> \\, ' -> \'
      safe = query |> String.replace("\\", "\\\\") |> String.replace("'", "\\'")
      soql = """
      SELECT Id, FirstName, LastName, Email, Phone, MobilePhone, Title,
             MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry, AccountId, PhotoUrl
      FROM Contact
      WHERE Name LIKE '%#{safe}%' OR Email LIKE '%#{safe}%'
      LIMIT 10
      """

      q = URI.encode(soql)
      path = "/services/data/v59.0/query?q=#{q}"

      case Tesla.get(client(cred), path) do
        {:ok, %Tesla.Env{status: 200, body: %{"records" => records}}} ->
          contacts = Enum.map(records, &format_contact(&1, cred))
          {:ok, contacts}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Gets a single contact by Id with standard fields.
  """
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      fields = Enum.join(@contact_fields, ",")
      path = "/services/data/v59.0/sobjects/Contact/#{contact_id}?fields=#{fields}"

      case Tesla.get(client(cred), path) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          {:ok, format_contact(body, cred)}

        {:ok, %Tesla.Env{status: 404, body: _}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @doc """
  Updates a contact's fields. `updates` is a map of Salesforce field names to values.
  """
  def update_contact(%UserCredential{} = credential, contact_id, updates) when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      path = "/services/data/v59.0/sobjects/Contact/#{contact_id}"

      case Tesla.patch(client(cred), path, updates) do
        {:ok, %Tesla.Env{status: 200, body: _}} ->
          get_contact(cred, contact_id)

        {:ok, %Tesla.Env{status: 404, body: _}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  defp format_contact(%{"Id" => id} = attrs, credential) do
    %{
      id: id,
      FirstName: attrs["FirstName"],
      LastName: attrs["LastName"],
      Email: attrs["Email"],
      Phone: attrs["Phone"],
      MobilePhone: attrs["MobilePhone"],
      Title: attrs["Title"],
      MailingStreet: attrs["MailingStreet"],
      MailingCity: attrs["MailingCity"],
      MailingState: attrs["MailingState"],
      MailingPostalCode: attrs["MailingPostalCode"],
      MailingCountry: attrs["MailingCountry"],
      AccountId: attrs["AccountId"],
      firstname: attrs["FirstName"],
      lastname: attrs["LastName"],
      email: attrs["Email"],
      display_name: format_display_name(attrs),
      avatar_url: resolve_photo_url(attrs["PhotoUrl"], credential)
    }
  end

  defp resolve_photo_url(nil, _), do: nil
  defp resolve_photo_url("", _), do: nil
  defp resolve_photo_url(url, %UserCredential{instance_url: base}) when is_binary(url) and is_binary(base) do
    if String.starts_with?(url, "http://") or String.starts_with?(url, "https://") do
      url
    else
      base = String.trim_trailing(base, "/")
      url = String.trim_leading(url, "/")
      "#{base}/#{url}"
    end
  end
  defp resolve_photo_url(url, _) when is_binary(url) do
    if String.starts_with?(url, "http://") or String.starts_with?(url, "https://"), do: url, else: nil
  end
  defp resolve_photo_url(_, _), do: nil

  defp format_display_name(attrs) do
    first = attrs["FirstName"] || ""
    last = attrs["LastName"] || ""
    email = attrs["Email"] || ""
    name = String.trim("#{first} #{last}")
    if name == "", do: email, else: name
  end

  defp with_token_refresh(%UserCredential{} = credential, api_call) do
    with {:ok, credential} <- SalesforceTokenRefresher.ensure_valid_token(credential) do
      case api_call.(credential) do
        {:error, {:api_error, 401, _body}} ->
          Logger.info("Salesforce token expired, refreshing and retrying...")
          retry_with_fresh_token(credential, api_call)

        other ->
          other
      end
    end
  end

  defp retry_with_fresh_token(credential, api_call) do
    case SalesforceTokenRefresher.refresh_credential(credential) do
      {:ok, refreshed} ->
        api_call.(refreshed)

      {:error, reason} ->
        Logger.error("Failed to refresh Salesforce token: #{inspect(reason)}")
        {:error, {:token_refresh_failed, reason}}
    end
  end
end
