defmodule TheBackendWeb.PromptController do
  use TheBackendWeb, :controller

  @system_instruction """
  You are a WebGL code generator. Your task is to generate WebGL code that renders shapes or effects based on user instructions. Follow these rules:

  1. **Canvas Size**: All output must fit within a 500x500 canvas. Coordinates should be normalized or scaled to this size.

  2. **Output Components**: For every request, you must generate:
     - A **vertex shader** that processes vertex positions.
     - A **fragment shader** that determines pixel colors.
     - **Vertex data** (e.g., positions, indices) for the shape or effect.
     - **Uniforms and attributes** required for the shaders.

  3. **WebGL Version**: Use **WebGL 1.0** for compatibility. Ensure the code adheres to WebGL 1.0 specifications.

  4. **Constraints**:
     - Keep the code minimal and self-contained.
     - Avoid unnecessary complexity or external dependencies.
     - Use `gl_Position` in the vertex shader to output clip-space coordinates.
     - Use `gl_FragColor` in the fragment shader to output pixel colors.
     - Normalize coordinates to the 500x500 canvas where applicable.

  5. **Examples**:
     - If the user asks for a "rotating cube," generate vertex and fragment shaders for a cube, along with its vertex data and required uniforms.
     - If the user asks for a "gradient background," generate fragment shader code to create a gradient within the 500x500 canvas.

  Always respond with only the required WebGL code (vertex shader, fragment shader, vertex data, and uniforms/attributes). Do not include explanations or additional text unless explicitly asked.
  """

  @generation_config %{
    "response_mime_type" => "application/json",
    "response_schema" => %{
      "type" => "OBJECT",
      "properties" => %{
        "vertex_shader" => %{
          "type" => "STRING",
          "description" => "The vertex shader code in GLSL."
        },
        "fragment_shader" => %{
          "type" => "STRING",
          "description" => "The fragment shader code in GLSL."
        },
        "vertex_data" => %{
          "type" => "OBJECT",
          "properties" => %{
            "positions" => %{
              "type" => "ARRAY",
              "items" => %{
                "type" => "NUMBER"
              },
              "description" => "Vertex positions as an array of numbers."
            },
            "indices" => %{
              "type" => "ARRAY",
              "items" => %{
                "type" => "NUMBER"
              },
              "description" => "Vertex indices as an array of numbers (optional)."
            }
          },
          "required" => ["positions"],
          "description" => "Vertex data including positions and optional indices."
        },
        "uniforms" => %{
          "type" => "OBJECT",
          "properties" => %{
            "u_resolution" => %{
              "type" => "ARRAY",
              "items" => %{
                "type" => "NUMBER"
              },
              "description" => "Canvas resolution as [width, height]."
            },
            "u_time" => %{
              "type" => "NUMBER",
              "description" => "Time uniform for animations (optional)."
            }
          },
          "required" => ["u_resolution"],
          "description" => "Uniforms required for the shaders."
        },
        "attributes" => %{
          "type" => "OBJECT",
          "properties" => %{
            "a_position" => %{
              "type" => "ARRAY",
              "items" => %{
                "type" => "NUMBER"
              },
              "description" => "Vertex position attribute."
            }
          },
          "required" => ["a_position"],
          "description" => "Attributes required for the shaders."
        }
      },
      "required" => [
        "vertex_shader",
        "fragment_shader",
        "vertex_data",
        "uniforms",
        "attributes"
      ],
      "description" => "Structured WebGL code for rendering shapes or effects."
    }
  }

  @gemini_api_url "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
  @api_key System.get_env("GEMINI_API_KEY")

  def process(conn, %{"prompt" => prompt}) do
    case call_llm_api(prompt) do
      {:ok, response_body} ->
        case extract_webgl_response(response_body) do
          {:ok, webgl_response} ->
            json(conn, %{response: webgl_response})

          {:error, reason} ->
            conn
            |> put_status(:bad_request)
            |> json(%{error: reason})
        end

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: reason})
    end
  end

  defp extract_webgl_response(response_body) do
    with %{"candidates" => [%{"content" => %{"parts" => [%{"text" => json_string}]}} | _]} <-
           response_body,
         {:ok, webgl_map} <- Jason.decode(json_string) do
      {:ok, webgl_map}
    else
      _ -> {:error, "Invalid or unexpected response structure from Gemini API"}
    end
  end

  defp call_llm_api(prompt) do
    url = "#{@gemini_api_url}?key=#{@api_key}"
    headers = [{"Content-Type", "application/json"}]

    body = %{
      "contents" => [
        %{
          "parts" => [%{"text" => prompt}]
        }
      ],
      "system_instruction" => %{
        "parts" => [%{"text" => @system_instruction}]
      },
      "generationConfig" => @generation_config
    }

    case Req.post(url, json: body, headers: headers, receive_timeout: 10_000) do
      {:ok, %{status: 200, body: response_body}} ->
        # Success
        {:ok, response_body}

      {:ok, %{status: status, body: error_body}} ->
        # Handle API errors
        {:error, "API returned status #{status}: #{inspect(error_body)}"}

      {:error, reason} ->
        # Handle connection errors
        {:error, "Failed to connect to Gemini API: #{inspect(reason)}"}
    end
  end
end
