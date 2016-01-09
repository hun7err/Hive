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

    def run() do
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

    defp rankedNodes(nodes, scheduling) do
      ranked_node_list = (for node <- nodes, do: calculateRank node, scheduling) |> Enum.sort
    end
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

    defmodule Swarm do
    end
  end
end
