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

    5. **Default Values**:
       - Use the following default values unless explicitly overridden by the user:
         - `u_resolution`: [500.0, 500.0]
         - `u_time`: 0.0
         - `u_color`: [1.0, 0.0, 0.0, 1.0] (red)
         - Camera position: [0, 0, 5]
         - Camera target: [0, 0, 0]
         - Scene background color: [0.1, 0.1, 0.1, 1.0] (dark gray)
         - Mesh scale: [1, 1, 1]

    6. **Examples**:
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
            },
            "dimensionality" => %{
              "type" => "NUMBER",
              "description" => "Dimensionality of vertex positions (2 for 2D, 3 for 3D)."
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
            },
            "u_color" => %{
              "type" => "ARRAY",
              "items" => %{"type" => "NUMBER"},
              "description" => "Default color as [r, g, b, a]."
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
        },
        "camera" => %{
          "type" => "OBJECT",
          "properties" => %{
            "position" => %{
              "type" => "ARRAY",
              "items" => %{"type" => "NUMBER"},
              "description" => "Camera position as [x, y, z]."
            },
            "target" => %{
              "type" => "ARRAY",
              "items" => %{"type" => "NUMBER"},
              "description" => "Camera target as [x, y, z]."
            }
          }
        },
        "scene" => %{
          "type" => "OBJECT",
          "properties" => %{
            "background_color" => %{
              "type" => "ARRAY",
              "items" => %{"type" => "NUMBER"},
              "description" => "Scene background color as [r, g, b, a]."
            }
          }
        },
        "mesh" => %{
          "type" => "OBJECT",
          "properties" => %{
            "scale" => %{
              "type" => "ARRAY",
              "items" => %{"type" => "NUMBER"},
              "description" => "Mesh scale as [x, y, z]."
            }
          }
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
  # System.get_env("GEMINI_API_KEY")

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
      {:ok, apply_defaults(webgl_map)}
    else
      _ -> {:error, "Invalid or unexpected response structure from Gemini API"}
    end
  end

  defp apply_defaults(response) do
    defaults = %{
      "uniforms" => %{
        "u_resolution" => [500.0, 500.0],
        "u_time" => 0.0,
        "u_color" => [1.0, 0.0, 0.0, 1.0]
      },
      "camera" => %{
        "position" => [0, 0, 5],
        "target" => [0, 0, 0]
      },
      "scene" => %{
        "background_color" => [0.1, 0.1, 0.1, 1.0]
      },
      "mesh" => %{
        "scale" => [1, 1, 1]
      },
      "vertex_data" => %{
        "dimensionality" => 2
      }
    }

    # Merge the response with defaults, preferring the response values
    deep_merge(defaults, response)
  end

  defp deep_merge(left, right) do
    Map.merge(left, right, fn _key, left_val, right_val ->
      if is_map(left_val) and is_map(right_val) do
        deep_merge(left_val, right_val)
      else
        right_val
      end
    end)
  end

  defp call_llm_api(prompt) do
    api_key = TheBackend.Config.gemini_api_key()
    url = "#{@gemini_api_url}?key=#{api_key}"

    IO.inspect(url, label: "Gemini API URL")
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
