defmodule TheBackend.Config do
  @moduledoc """
  Handles runtime configuration for the app.
  """

  @doc """
  Fetches the GEMINI_API_KEY environment variable at runtime.
  """
  def gemini_api_key do
    System.get_env("GEMINI_API_KEY") ||
      raise """
      environment variable GEMINI_API_KEY is missing.
      """
  end
end