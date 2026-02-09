defmodule Ueberauth.Strategy.Salesforce do
  @moduledoc """
  Salesforce Strategy for Ueberauth.

  Stores instance_url, token, refresh_token, expires_at from the token response
  for use in API calls.
  """

  use Ueberauth.Strategy,
    uid_field: :id,
    default_scope: "api refresh_token offline_access",
    oauth2_module: Ueberauth.Strategy.Salesforce.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  require Logger

  @pkce_ttl_seconds 600

  @doc """
  Handles initial request for Salesforce authentication.
  Uses PKCE (RFC 7636) for compatibility with Salesforce Connected Apps that require it.
  Stores code_verifier in ETS keyed by state to avoid session cookie round-trip issues.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)
    code_verifier = generate_code_verifier()
    code_challenge = generate_code_challenge(code_verifier)
    state = conn.private[:ueberauth_state_param]
    if state do
      :ets.insert(:ueberauth_salesforce_pkce, {state, {code_verifier, System.system_time(:second)}})
    end

    opts =
      [scope: scopes, redirect_uri: callback_url(conn)]
      |> with_optional(:prompt, conn)
      |> with_param(:prompt, conn)
      |> with_state_param(conn)
      |> Keyword.put(:code_challenge, code_challenge)
      |> Keyword.put(:code_challenge_method, "S256")

      authorize_url = Ueberauth.Strategy.Salesforce.OAuth.authorize_url!(opts)

      # need to delete for production
      Logger.info("[Salesforce] Sending auth request: redirect_uri=#{callback_url(conn)}, state=#{inspect(state)}, scope=#{inspect(scopes)}")
      Logger.debug("[Salesforce] Full authorize URL: #{inspect(authorize_url)}")

      IO.inspect(label: "authorize_url!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!", authorize_url: authorize_url)
      redirect!(conn, authorize_url)
  end

  @doc """
  Handles the callback from Salesforce.
  Uses code_verifier from ETS (keyed by state) to exchange the authorization code for tokens.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code, "state" => state}} = conn) do
    code_verifier = fetch_and_delete_code_verifier(state)

    if is_nil(code_verifier) do
      set_errors!(conn, [
        error("missing_code_verifier", "PKCE verifier expired or invalid. Please try connecting again.")
      ])
    else
      opts = [redirect_uri: callback_url(conn)]
      token_params = [code: code, code_verifier: code_verifier]

      case Ueberauth.Strategy.Salesforce.OAuth.get_access_token(token_params, opts) do
        {:ok, token} ->
          user_info = fetch_user_info(token)
          Logger.info("[Salesforce] UserInfo: #{inspect(user_info)}")
          # need to delete for production
          Logger.info("[Salesforce] Callback: token exchange succeeded, instance_url=#{inspect(token.other_params["instance_url"])}")
          Logger.debug("[Salesforce] Callback: token response keys=#{inspect(Map.keys(token.other_params))}")

          conn
          |> put_private(:salesforce_token, token)
          |> put_private(:salesforce_user, user_from_token(token, user_info))

        {:error, {error_code, error_description}} when is_binary(error_description) ->
          Logger.error("Salesforce token exchange failed: #{error_code} - #{error_description}")
          set_errors!(conn, [error(error_code, error_description)])

        {:error, {error_code, error_description}} ->
          Logger.error("Salesforce token exchange failed: #{inspect({error_code, error_description})}")
          set_errors!(conn, [error(to_string(error_code), to_string(error_description))])
      end
    end
  end

  def handle_callback!(%Plug.Conn{params: %{"code" => _code}} = conn) do
    set_errors!(conn, [
      error("missing_state", "PKCE verifier expired or invalid. Please try connecting again.")
    ])
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc """
  Cleans up the private area of the connection used for passing the raw Salesforce response.
  """
  def handle_cleanup!(conn) do
    conn
    |> put_private(:salesforce_token, nil)
    |> put_private(:salesforce_user, nil)
  end

  @doc """
  Fetches the uid field from the response. Salesforce uses the identity URL or id from token.
  """
  def uid(conn) do
    user = conn.private.salesforce_user
    uid_field = option(conn, :uid_field) |> to_string()
    Map.get(user, uid_field) || token(conn).other_params["id"]
  end

  @doc """
  Includes the credentials from the Salesforce response.
  other_params contains instance_url, id, etc.
  """
  def credentials(conn) do
    token = conn.private.salesforce_token

    expires_at =
      if token.expires_at do
        token.expires_at
      else
        case Map.get(token.other_params || %{}, "expires_in") do
          nil -> nil
          secs when is_integer(secs) -> DateTime.add(DateTime.utc_now(), secs, :second)
          secs when is_binary(secs) -> DateTime.add(DateTime.utc_now(), String.to_integer(secs), :second)
        end
      end

    %Credentials{
      expires: true,
      expires_at: expires_at,
      scopes: (token.other_params["scope"] || "") |> String.split(" ", trim: true),
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: token.token_type
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private.salesforce_user

    %Info{
      email: user["email"] || user["preferred_username"],
      name: user["display_name"] || user["name"] || user["preferred_username"]
    }
  end

  @doc """
  Stores the raw information obtained from the Salesforce callback.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private.salesforce_token,
        user: conn.private.salesforce_user
      }
    }
  end

  defp token(conn), do: conn.private.salesforce_token

  defp user_from_token(%OAuth2.AccessToken{other_params: params}, user_info) when is_map(params) do
    # Salesforce token response includes id (user id), instance_url, etc.
    # UserInfo API provides email, preferred_username, display_name, etc.
    %{
      "id" => params["id"],
      "instance_url" => params["instance_url"],
      "email" => user_info["email"] || params["email"],
      "preferred_username" => user_info["preferred_username"] || params["preferred_username"],
      "display_name" => user_info["name"] || user_info["display_name"] || params["display_name"],
      "name" => user_info["name"] || params["name"]
    }
  end

  defp user_from_token(_, _), do: %{}

  defp fetch_user_info(%OAuth2.AccessToken{access_token: access_token, other_params: %{"instance_url" => instance_url}}) do
    userinfo_url = String.trim_trailing(instance_url, "/") <> "/services/oauth2/userinfo"

    client = Tesla.client([
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{access_token}"}]}
    ])

    case Tesla.get(client, userinfo_url) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_map(body) ->
        body

      {:ok, %Tesla.Env{status: status, body: body}} ->
        Logger.warn("[Salesforce] UserInfo API returned status #{status}: #{inspect(body)}")
        %{}

      {:error, reason} ->
        Logger.error("[Salesforce] UserInfo API error: #{inspect(reason)}")
        %{}
    end
  end

  defp fetch_user_info(_), do: %{}

  defp with_param(opts, key, conn) do
    if value = conn.params[to_string(key)], do: Keyword.put(opts, key, value), else: opts
  end

  defp with_optional(opts, key, conn) do
    if option(conn, key), do: Keyword.put(opts, key, option(conn, key)), else: opts
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end

  # PKCE helpers (RFC 7636)
  defp generate_code_verifier do
    32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false) |> binary_part(0, 43)
  end

  defp generate_code_challenge(code_verifier) do
    :crypto.hash(:sha256, code_verifier) |> Base.url_encode64(padding: false)
  end

  defp fetch_and_delete_code_verifier(state) when is_binary(state) do
    case :ets.lookup(:ueberauth_salesforce_pkce, state) do
      [{^state, {code_verifier, inserted_at}}] ->
        :ets.delete(:ueberauth_salesforce_pkce, state)
        if System.system_time(:second) - inserted_at <= @pkce_ttl_seconds do
          code_verifier
        else
          nil
        end

      [] ->
        nil
    end
  end

  defp fetch_and_delete_code_verifier(_), do: nil
end
