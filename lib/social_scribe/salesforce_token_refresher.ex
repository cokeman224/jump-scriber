defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Refreshes Salesforce OAuth tokens.
  Uses instance_url from the credential to determine production vs sandbox token endpoint.
  """

  def client do
    Tesla.client([
      {Tesla.Middleware.FormUrlencoded,
       encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1},
      Tesla.Middleware.JSON
    ])
  end

  defp token_url(instance_url) do
    if instance_url && String.contains?(to_string(instance_url), "test.salesforce.com") do
      "https://test.salesforce.com/services/oauth2/token"
    else
      "https://login.salesforce.com/services/oauth2/token"
    end
  end

  @doc """
  Refreshes a Salesforce access token using the refresh token.
  Uses instance_url to hit the correct endpoint (production or sandbox).
  Returns {:ok, response_body} with access_token, instance_url, id, expires_in, etc.
  """
  def refresh_token(refresh_token_string, instance_url) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])
    client_id = config[:client_id]
    client_secret = config[:client_secret]

    body = %{
      grant_type: "refresh_token",
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token_string
    }

    url = token_url(instance_url)

    case Tesla.post(client(), url, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {status, error_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Refreshes the token for a Salesforce credential and updates it in the database.
  """
  def refresh_credential(credential) do
    alias SocialScribe.Accounts

    case refresh_token(credential.refresh_token, credential.instance_url) do
      {:ok, response} ->
        expires_at =
          case response["expires_in"] do
            nil -> credential.expires_at
            secs when is_integer(secs) -> DateTime.add(DateTime.utc_now(), secs, :second)
            secs when is_binary(secs) -> DateTime.add(DateTime.utc_now(), String.to_integer(secs), :second)
          end

        attrs = %{
          token: response["access_token"],
          expires_at: expires_at
        }

        attrs =
          if response["instance_url"],
            do: Map.put(attrs, :instance_url, response["instance_url"]),
            else: attrs

        Accounts.update_user_credential(credential, attrs)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ensures a credential has a valid (non-expired) token.
  Refreshes if expired or about to expire (within 5 minutes).
  """
  def ensure_valid_token(credential) do
    buffer_seconds = 300

    if DateTime.compare(
         credential.expires_at,
         DateTime.add(DateTime.utc_now(), buffer_seconds, :second)
       ) == :lt do
      refresh_credential(credential)
    else
      {:ok, credential}
    end
  end
end
