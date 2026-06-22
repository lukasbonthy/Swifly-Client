#include <std_include.hpp>
#include "loader/component_loader.hpp"
#include "updater.hpp"
#include "game/game.hpp"

#include <utils/flags.hpp>
#include <utils/progress_ui.hpp>
#include <updater/updater.hpp>

namespace updater {
namespace {
constexpr auto SERVER_BROWSER_LUA_URL =
    "https://swifly-servers.onrender.com/boiii/data/ui_scripts/server_browser/__init__.lua";

void remove_folder_if_exists(const std::filesystem::path &path,
                             const std::string &label) {
  std::error_code ec{};
  if (!std::filesystem::exists(path, ec)) {
    return;
  }

  std::filesystem::remove_all(path, ec);
  if (ec) {
    throw std::runtime_error("Failed to reset " + label + ": " +
                             path.string() + " (" + ec.message() + ")");
  }
}

std::string make_cache_busted_url(const std::string &url) {
  const auto now = std::chrono::system_clock::now().time_since_epoch().count();
  return url + "?swifly_force=" + std::to_string(now);
}

std::string hresult_to_hex(const HRESULT hr) {
  std::ostringstream out{};
  out << "0x" << std::hex << std::uppercase << static_cast<unsigned long>(hr);
  return out.str();
}

void download_url_to_file(const std::string &url, const std::filesystem::path &target,
                          const std::string &label) {
  std::error_code ec{};
  std::filesystem::create_directories(target.parent_path(), ec);
  if (ec) {
    throw std::runtime_error("Failed to create folder for " + label + ": " +
                             target.parent_path().string() + " (" +
                             ec.message() + ")");
  }

  std::filesystem::remove(target, ec);
  ec.clear();

  const auto target_string = target.string();
  const auto hr = URLDownloadToFileA(nullptr, url.c_str(), target_string.c_str(),
                                     0, nullptr);
  if (FAILED(hr)) {
    throw std::runtime_error("Failed to force download " + label + ": " + url +
                             " -> " + target_string + " (HRESULT " +
                             hresult_to_hex(hr) + ")");
  }

  if (!std::filesystem::exists(target, ec) ||
      std::filesystem::file_size(target, ec) == 0) {
    throw std::runtime_error("Forced download produced missing/empty file for " +
                             label + ": " + target_string);
  }
}

void force_download_server_browser_lua(const std::filesystem::path &appdata_path) {
  const auto url = make_cache_busted_url(SERVER_BROWSER_LUA_URL);
  const auto relative_lua = std::filesystem::path("data") / "ui_scripts" /
                            "server_browser" / "__init__.lua";

  download_url_to_file(url, appdata_path / relative_lua,
                       "Swifly appdata server browser Lua");
  download_url_to_file(url, game::get_game_path() / relative_lua,
                       "BO3 game-folder server browser Lua");
}

void hard_reset_download_cache(const std::filesystem::path &appdata_path) {
  remove_folder_if_exists(appdata_path / "data", "updater data cache");
}

void mirror_downloaded_data_to_game_folder(
    const std::filesystem::path &appdata_path) {
  const auto source_data = appdata_path / "data";
  const auto game_data = game::get_game_path() / "data";

  std::error_code ec{};
  if (!std::filesystem::exists(source_data, ec)) {
    throw std::runtime_error("Updater did not download a data folder: " +
                             source_data.string());
  }

  // The game/client loads loose UI scripts from the game folder's data path.
  // Force that folder to match the freshly downloaded Swifly updater data so
  // old cached Lua files cannot keep winning.
  remove_folder_if_exists(game_data, "game data folder");

  std::filesystem::create_directories(game_data.parent_path(), ec);
  if (ec) {
    throw std::runtime_error("Failed to create game data parent folder: " +
                             game_data.parent_path().string() + " (" +
                             ec.message() + ")");
  }

  std::filesystem::copy(source_data, game_data,
                        std::filesystem::copy_options::recursive |
                            std::filesystem::copy_options::overwrite_existing,
                        ec);
  if (ec) {
    throw std::runtime_error("Failed to mirror Swifly data into game folder: " +
                             source_data.string() + " -> " +
                             game_data.string() + " (" + ec.message() + ")");
  }
}
} // namespace

void update() {
  if (utils::flags::has_flag("noupdate")) {
    return;
  }

  try {
    const auto appdata_path = game::get_appdata_path();

    // Hard reset the cached updater data first.
    hard_reset_download_cache(appdata_path);

    // Directly pull the server browser Lua from swifly-servers.onrender.com
    // before the generic updater runs. This makes the target file exist even if
    // the normal manifest path is stale or skipped.
    force_download_server_browser_lua(appdata_path);

    // Run the normal updater for the rest of the data files.
    run(appdata_path);

    // Mirror all freshly downloaded updater data into the actual BO3 folder.
    mirror_downloaded_data_to_game_folder(appdata_path);

    // Overwrite the server browser Lua one final time from
    // swifly-servers.onrender.com so this exact hosted Lua wins after any
    // manifest/update/mirror behavior.
    force_download_server_browser_lua(appdata_path);
  } catch (update_cancelled &) {
    TerminateProcess(GetCurrentProcess(), 0);
  } catch (const std::exception &e) {
    utils::progress_ui::show_error("Updater Error", e.what());
  } catch (...) {
    utils::progress_ui::show_error("Updater Error",
                                   "Unknown error occurred during update.");
  }
}

class component final : public generic_component {
public:
  component() {
    // Do NOT run this in the background. It must finish before the frontend can
    // load old loose Lua from disk.
    update();
  }

  void pre_destroy() override {}
  void post_unpack() override {}

  component_priority priority() const override {
    return component_priority::updater;
  }
};
} // namespace updater

REGISTER_COMPONENT(updater::component)
