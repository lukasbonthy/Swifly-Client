#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "server_list.hpp"

#include "game/game.hpp"

#include "command.hpp"

#include <utils/string.hpp>
#include <utils/concurrency.hpp>
#include <utils/hook.hpp>
#include <utils/io.hpp>
#include <utils/http.hpp>

#include "network.hpp"
#include "scheduler.hpp"
#include "toast.hpp"

namespace server_list {
namespace {
utils::hook::detour lua_server_info_to_table_hook;

constexpr auto swifly_server_list_url = "https://client.swifly.net/servers.json";

utils::concurrency::container<server_list> favorite_servers{};
utils::concurrency::container<std::vector<game::net::netadr_t>>
    recent_servers{};

void add_server_from_string(std::unordered_set<game::net::netadr_t> &servers,
                            const std::string &address) {
  if (address.empty()) {
    return;
  }

  const auto addr = network::address_from_string(address);
  if (addr.type != game::net::NA_BAD) {
    servers.emplace(addr);
  }
}

std::unordered_set<game::net::netadr_t>
parse_http_server_list(const std::string &json) {
  std::unordered_set<game::net::netadr_t> servers{};

  rapidjson::Document doc{};
  doc.Parse(json.data(), json.size());

  if (doc.IsArray()) {
    for (const auto &entry : doc.GetArray()) {
      if (entry.IsString()) {
        add_server_from_string(
            servers, std::string(entry.GetString(), entry.GetStringLength()));
      }
    }
    return servers;
  }

  if (doc.IsObject() && doc.HasMember("servers") && doc["servers"].IsArray()) {
    for (const auto &entry : doc["servers"].GetArray()) {
      if (entry.IsString()) {
        add_server_from_string(
            servers, std::string(entry.GetString(), entry.GetStringLength()));
      }
    }
  }

  return servers;
}

std::string get_cache_buster() {
  return "?" +
         std::to_string(std::chrono::duration_cast<std::chrono::nanoseconds>(
                            std::chrono::system_clock::now().time_since_epoch())
                            .count());
}

void lua_server_info_to_table_stub(game::ui::lua::hks::lua_State *state,
                                   game::lobby::ServerInfo server_info,
                                   int index) {
  lua_server_info_to_table_hook.invoke(state, server_info, index);

  if (state) {
    const auto bot_count =
        atoi(game::info::Info_ValueForKey(server_info.tags, "bots"));
    game::ui::lua::Lua_SetTableInt("botCount", bot_count, state);

    const auto rounds =
        atoi(game::info::Info_ValueForKey(server_info.tags, "rounds"));
    game::ui::lua::Lua_SetTableInt("rounds", rounds, state);

    const auto *campaign_str =
        game::info::Info_ValueForKey(server_info.tags, "campaign");
    const auto is_campaign =
        campaign_str && std::strcmp(campaign_str, "true") == 0;
    game::ui::lua::Lua_SetTableInt("campaign", is_campaign ? 1 : 0, state);
  }
}

std::string get_favorite_servers_file_path() {
  return "boiii_players/user/favorite_servers.txt";
}

std::string get_recent_servers_file_path() {
  return "boiii_players/user/recent_servers.txt";
}

void write_favorite_servers() {
  favorite_servers.access(
      [](const std::unordered_set<game::net::netadr_t> &servers) {
        std::string servers_buffer{};
        for (const auto &itr : servers) {
          servers_buffer.append(
              utils::string::va("%i.%i.%i.%i:%hu\n", itr.ipv4.a, itr.ipv4.b,
                                itr.ipv4.c, itr.ipv4.d, itr.port));
        }

        utils::io::write_file(get_favorite_servers_file_path(), servers_buffer);
      });
}

void read_favorite_servers() {
  const std::string path = get_favorite_servers_file_path();
  if (!utils::io::file_exists(path)) {
    return;
  }

  favorite_servers.access(
      [&path](std::unordered_set<game::net::netadr_t> &servers) {
        servers.clear();

        std::string data;
        if (utils::io::read_file(path, &data)) {
          const auto srv = utils::string::split(data, '\n');
          for (const auto &server_address : srv) {
            const auto server = network::address_from_string(server_address);
            if (server.type != game::net::NA_BAD) {
              servers.insert(server);
            }
          }
        }
      });
}

void write_recent_servers() {
  recent_servers.access([](const std::vector<game::net::netadr_t> &servers) {
    std::string servers_buffer{};
    for (const auto &itr : servers) {
      servers_buffer.append(utils::string::va("%i.%i.%i.%i:%hu\n", itr.ipv4.a,
                                              itr.ipv4.b, itr.ipv4.c,
                                              itr.ipv4.d, itr.port));
    }
    utils::io::write_file(get_recent_servers_file_path(), servers_buffer);
  });
}

void read_recent_servers() {
  const std::string path = get_recent_servers_file_path();
  if (!utils::io::file_exists(path)) {
    return;
  }

  recent_servers.access([&path](std::vector<game::net::netadr_t> &servers) {
    servers.clear();
    servers.reserve(64);

    std::string data;
    if (utils::io::read_file(path, &data)) {
      const auto srv = utils::string::split(data, '\n');
      for (const auto &server_address : srv) {
        if (server_address.empty()) {
          continue;
        }

        const auto server = network::address_from_string(server_address);
        if (server.type == game::net::NA_BAD) {
          continue;
        }

        servers.emplace_back(server);
        if (servers.size() >= 50) {
          break;
        }
      }
    }
  });
}

std::string get_lan_servers_file_path() {
  return "boiii_players/user/lan_servers.txt";
}

std::string normalize_lan_input(std::string in) {
  in.erase(std::remove(in.begin(), in.end(), '\r'), in.end());
  in.erase(std::remove(in.begin(), in.end(), '\n'), in.end());
  if (in.empty()) {
    return {};
  }

  if (in.find(':') == std::string::npos) {
    in.append(":27017");
  }

  return in;
}

void add_lan_server_from_string(const std::string &in) {
  const auto normalized = normalize_lan_input(in);
  if (normalized.empty()) {
    return;
  }

  const auto addr = network::address_from_string(normalized);
  if (addr.type == game::net::NA_BAD) {
    return;
  }

  std::string data;
  utils::io::read_file(get_lan_servers_file_path(), &data);
  const auto lines = utils::string::split(data, '\n');

  std::vector<std::string> out{};
  out.reserve(lines.size() + 1);

  bool already_present = false;
  for (const auto &line : lines) {
    const auto l = normalize_lan_input(line);
    if (l.empty()) {
      continue;
    }
    if (l == normalized) {
      already_present = true;
    }
    out.emplace_back(l);
  }

  if (!already_present) {
    out.emplace_back(normalized);
  }

  std::string write;
  for (const auto &l : out) {
    write.append(l);
    write.push_back('\n');
  }
  utils::io::write_file(get_lan_servers_file_path(), write);
}
} // namespace

std::vector<game::net::netadr_t> get_master_servers() {
  return {network::address_from_string("client.swifly.net:20810")};
}

void request_servers(callback callback) {
  std::thread([cb = std::move(callback)]() mutable {
    std::unordered_set<game::net::netadr_t> servers{};

    const auto json =
        utils::http::get_data(swifly_server_list_url + get_cache_buster());
    if (json) {
      servers = parse_http_server_list(*json);
    }

    cb(!servers.empty(), servers);
  }).detach();
}

void add_favorite_server(game::net::netadr_t addr) {
  favorite_servers.access(
      [&addr](std::unordered_set<game::net::netadr_t> &servers) {
        servers.insert(addr);
      });
  write_favorite_servers();
}

void remove_favorite_server(game::net::netadr_t addr) {
  favorite_servers.access(
      [&addr](std::unordered_set<game::net::netadr_t> &servers) {
        for (auto it = servers.begin(); it != servers.end(); ++it) {
          if (network::are_addresses_equal(*it, addr)) {
            servers.erase(it);
            break;
          }
        }
      });
  write_favorite_servers();
}

utils::concurrency::container<server_list> &get_favorite_servers() {
  return favorite_servers;
}

void add_recent_server(game::net::netadr_t addr) {
  recent_servers.access([&addr](std::vector<game::net::netadr_t> &servers) {
    for (auto it = servers.begin(); it != servers.end(); ++it) {
      if (network::are_addresses_equal(*it, addr)) {
        servers.erase(it);
        break;
      }
    }

    servers.insert(servers.begin(), addr);
    if (servers.size() > 50) {
      servers.resize(50);
    }
  });

  write_recent_servers();
}

void remove_recent_server(game::net::netadr_t addr) {
  recent_servers.access([&addr](std::vector<game::net::netadr_t> &servers) {
    for (auto it = servers.begin(); it != servers.end(); ++it) {
      if (network::are_addresses_equal(*it, addr)) {
        servers.erase(it);
        break;
      }
    }
  });

  write_recent_servers();
}

utils::concurrency::container<recent_list> &get_recent_servers() {
  return recent_servers;
}

struct component final : client_component {
  void post_unpack() override {
    lua_server_info_to_table_hook.create(0x141F1FD10_g,
                                         lua_server_info_to_table_stub);

    scheduler::once(
        [] {
          read_favorite_servers();
          read_recent_servers();
        },
        scheduler::main);

    command::add("lan_add", [](const command::params &params) {
      if (params.size() < 2) {
        return;
      }

      add_lan_server_from_string(params.get(1));
      toast::show("Server List",
                  utils::string::va("Added LAN server: %s", params.get(1)),
                  "t7_icon_connect_overlays");
    });
  }

  void pre_destroy() override {}
};
} // namespace server_list

REGISTER_COMPONENT(server_list::component)
