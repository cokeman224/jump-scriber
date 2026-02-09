defmodule SocialScribeWeb.Plugs.Redirect do
  @moduledoc """
  A plug that redirects to a configured path.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    path = Keyword.fetch!(opts, :to)
    Phoenix.Controller.redirect(conn, to: path) |> halt()
  end
end
