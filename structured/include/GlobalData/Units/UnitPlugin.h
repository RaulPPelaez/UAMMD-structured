#pragma once
#include <functional>
#include <memory>
#include <string>

namespace uammd {
namespace structured {
namespace plugins {

class BaseUnit
{
public:
    virtual float getBoltzmannConstant() = 0;
    virtual float getElectricConversionFactor() = 0;
};

void registerUnitPlugin(std::function<std::shared_ptr<BaseUnit>(std::string)>, std::string identifier);

} // namespace plugins
} // namespace structured
} // namespace uammd

#define REGISTER_UNIT_PLUGIN(creator, identifier)                                                                      \
    namespace {                                                                                                        \
    struct UnitPluginRegistrar                                                                                         \
    {                                                                                                                  \
        UnitPluginRegistrar()                                                                                          \
        {                                                                                                              \
            uammd::structured::plugins::registerUnitPlugin(creator, identifier);                                       \
        }                                                                                                              \
    } unitPluginRegistrar;                                                                                             \
    } // namespace
