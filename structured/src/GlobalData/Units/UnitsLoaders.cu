#include "GlobalData/Units/UnitsLoaders.cuh"

namespace uammd{
namespace structured{
namespace UnitsLoader{

    bool isUnitsAvailable(std::shared_ptr<ExtendedSystem> sys,
                          std::vector<std::string>       path){

        DataEntry data = sys->getInput()->getDataEntry(path);

        std::string typesType    = data.getType();
        std::string typesSubType = data.getSubType();

        return Units::UnitsFactory::getInstance().isUnitsRegistered(typesType,typesSubType);
    }


    std::shared_ptr<typename Units::UnitsHandler>
    loadUnits(std::shared_ptr<ExtendedSystem> sys,
              std::vector<std::string>       path){
      std::cerr<<"Loading path: ";
      for(const auto& p : path) {
	std::cerr << p << " ";
      }
      std::cerr << std::endl;
        DataEntry data = sys->getInput()->getDataEntry(path);

        std::string typesType    = data.getType();
        std::string typesSubType = data.getSubType();

        //////////////////////////////////////////////////////////////

        return Units::UnitsFactory::getInstance().createUnits(typesType,typesSubType,
                                                              data);
    }

}}}
