#include "GlobalData/Units/UnitPlugin.h"
#include "GlobalData/Units/UnitsFactory.cuh"
#include "GlobalData/Units/UnitsHandler.cuh"

namespace uammd {
namespace structured {
namespace plugins {

class UnitPluginWrapper : public uammd::structured::Units::UnitsHandler
{
    std::shared_ptr<BaseUnit> b;

public:
  UnitPluginWrapper(std::shared_ptr<BaseUnit> b, uammd::structured::DataEntry& data):UnitsHandler(data), b(b)
    {
    }

    real getBoltzmannConstant() override
    {
        return b->getBoltzmannConstant();
    }
    real getElectricConversionFactor() override
    {
        return b->getElectricConversionFactor();
    }
};


void registerUnitPlugin(std::function<std::shared_ptr<BaseUnit>(json)> creator, std::string identifier)
{
    uammd::structured::PluginUtils::registrationGuard(identifier, "external");
    uammd::structured::Units::UnitsFactory::getInstance().registerUnits(
									"Units", identifier, [creator](uammd::structured::DataEntry& data) {
      const auto& datamap = *data.data;
      auto b = creator(datamap);
        return std::make_shared<UnitPluginWrapper>(b,data);
        });
}

} // namespace plugins
} // namespace structured
} // namespace uammd
