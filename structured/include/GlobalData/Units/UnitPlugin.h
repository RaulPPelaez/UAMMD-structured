#pragma once
#include <memory>
#include <string>
#include "ThirdParty/json.hpp"
#include <functional>

namespace uammd {
namespace structured {
namespace plugins {

  using json = nlohmann::json;

class BaseUnit
{
public:
    virtual float getBoltzmannConstant() = 0;
    virtual float getElectricConversionFactor() = 0;
};

  void registerUnitPlugin(std::function<std::shared_ptr<BaseUnit>(json)>, std::string identifier);

} // namespace plugins
} // namespace structured
} // namespace uammd
