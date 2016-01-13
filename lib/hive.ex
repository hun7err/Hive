defmodule Hacks do
  defp dirtyHack(what, method), do: :crypto.hash(method, what)
  def getId() do
    :os.timestamp
      |> Tuple.to_list
      |> Enum.join
      |> dirtyHack(:sha)
      |> Base.encode16
      |> String.downcase
  end
end

defmodule Hive do
  require Record

  # scheduling - :even_spread, :random_pick, :optimize
  defmodule Cluster do
    defstruct name: Hacks.getId,
              nodes: [],
              scheduling: :even_spread

    def run(cluster, name, link \\ [], image \\ "ubuntu", cmd \\ "/bin/bash") do
      target = hd rankedNodes(cluster)
      Hive.Docker.run target, name, link, image, cmd
    end

    defp getContainerCount(node) do
      try do
        container_count = Hive.Docker.containers(node) |> length
      rescue
        e in HTTPotion.HTTPError -> -1
      end
    end

    defp calculateRank(node, scheduling) do
      case scheduling do
        :even_spread ->
          getContainerCount node
        :random_pick ->
          :random.uniform
        :optimize ->
          0 # TODO: add some algorithm with weights
      end
    end

    defp rankedNodes(cluster) do
      cluster.nodes
        |> Enum.sort(&(calculateRank(&1, cluster.scheduling) > calculateRank(&2, cluster.scheduling)))
    end
  end

  defmodule Node do
    defstruct host: "127.0.0.1", port: 2375
  end

  defmodule Docker do
    defmodule Container do
      defstruct id: "", node: nil
    end

    defp getUrl(docker_node, uri) do
      docker_node.host <> ":" <> to_string(docker_node.port) <> uri
    end

    defp endpoint(docker_node, method, name,
                  data \\ [],
                  url_params \\ %{},
                  headers \\ ["Content-Type": "application/json",
                              "Accept": "application/json"]) do
      suffix = if name in ["containers", "images"], do: "/json", else: ""
      try do
        case method do
          "get" ->
            uri = "/" <> name <> suffix
            response = HTTPotion.get getUrl(docker_node, uri)
            
            case response.status_code do
              200 -> {:ok, response}
              _ -> {:error, response}
            end
          "post" ->
            params = for {key, value} <- url_params, do: to_string(key) <> "=" <> to_string(value)
            
            params = if url_params != %{}, do: "?" <> Enum.join(params, "&"), else: ""
            IO.puts "[debug] trying " <> "/" <> name <> params
            response = HTTPotion.post getUrl(docker_node,
                                             "/" <> name <> params),
                                      [body: Poison.encode!(data),
                                       headers: headers]

            case response.status_code do
              code when code in [200, 201, 204] -> {:ok, response}
              _ -> {:error, response}
            end
          _ -> {:error, "unsupported http method"}
        end
      rescue
        e in HTTPoison.HTTPError -> {:error, e.message}
      end
    end

    defp handleEndpointResponse(output, handler \\ &Poison.Parser.parse!/1)
        when is_function(handler) do
      case output do
        {:ok, response} ->
          handler.(response.body)
        {:error, response} ->
          raise to_string(response.status_code) <> ": " <> response.body
      end
    end

    def info(docker_node) do
      endpoint(docker_node, "get", "info")
        |> handleEndpointResponse
    end

    def containers(docker_node) do
      endpoint(docker_node, "get", "containers")
        |> handleEndpointResponse
    end

    def images(docker_node) do
       endpoint(docker_node, "get", "images")
        |> handleEndpointResponse
    end

    def create(docker_node, name, links \\ [], image \\ "ubuntu:latest", cmd \\ "/bin/bash") do
      data = %{"Image": image, 
               "Tty": true,
               "HostConfig":
                  %{"Links": links},
               "Cmd": cmd }

      result = endpoint(docker_node, "post", "containers/create", data, %{"name": String.replace(name, " ", "-")})
          |> handleEndpointResponse
      
      case result do
        response_json ->
          case Dict.fetch(response_json, "Id") do
            {:ok, container_id} ->
              %Hive.Docker.Container{"id": container_id, "node": docker_node}
            _ -> raise RuntimeError
          end
        _ ->
          "I didn't expect the Spanish Inquisition!"
      end
    end

    def start(container) do
      result = endpoint(container.node, "post", "containers/" <> container.id <> "/start", %{})

      case result do
        {:ok, response} ->
          case response.status_code do
            204 ->
              {:started, container}
            304 ->
              {:already_started, nil}
            404 ->
              {:nocontainer, nil}
            500 ->
              {:internal_server_error, nil}
          end
        error ->
          error
      end 
    end

    def run(docker_node, name, link \\ [], image \\ "ubuntu", cmd \\ "/bin/bash") do
      container = create docker_node, name, link, image, cmd
      start container
    end
  end
end
