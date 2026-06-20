#include <std_include.hpp>
#include "loader/component_loader.hpp"

#include <utils/io.hpp>

namespace swifly_master {
namespace {
constexpr auto master_servers_path = "boiii_players/user/master_servers.txt";
constexpr auto swifly_master_servers = "client.swifly.net:20810\n";

void write_swifly_master_servers() {
  utils::io::write_file(master_servers_path, swifly_master_servers);
}
} // namespace

struct component final : client_component {
  void post_unpack() override { write_swifly_master_servers(); }
};
} // namespace swifly_master

REGISTER_COMPONENT(swifly_master::component)
