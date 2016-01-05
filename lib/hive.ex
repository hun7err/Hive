defmodule Hive do
  require Record

  defmodule Cluster do
  end

  defmodule Node do
    defstruct host: "127.0.0.1", port: 2375
  end

  defmodule Docker do
    defp getUrl(docker_node, uri) do
      docker_node.host <> ":" <> to_string(docker_node.port) <> uri
    end

    def info(docker_node) do
      response = HTTPotion.get getUrl(docker_node, "/info")
      Poison.Parser.parse! response.body
    end

    def containers(docker_node) do
      response = HTTPotion.get getUrl(docker_node, "/containers/json")
      Poison.Parser.parse! response.body
    end

    def create(docker_node, name, image \\ "ubuntu", cmd \\ "/bin/bash") do
      data = %{"Image": image, "Cmd": cmd }
      response = HTTPotion.post getUrl(docker_node,
                                      "/containers/create?name=" <> name),
                                [body: Poison.encode!(data),
                                 headers: ["Content-Type": "application/json"]
                                ]

      case response.status_code do
        201 ->
          resp_json = Poison.Parser.parse! response.body
      
          case Dict.fetch(resp_json, "Id") do
            {:ok, container_id} -> container_id
            :error -> raise RuntimeError
          end
        _ -> raise RuntimeError
      end
    end

    defmodule Container do
    end
  end
end
