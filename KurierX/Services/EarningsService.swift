import Foundation

enum EarningsService {
  static func routeBaseHellers(type: RouteType, orders: Int) -> Int64 {
    let p: Int64
    switch type {
    case .ot: p = 4200
    case .region: p = 4700
    case .express: p = 5200
    }
    return Int64(max(0, orders)) * p
  }
  static func routeGross(_ route: Route) -> Int64 {
    routeBaseHellers(type: route.type, orders: route.factualOrders)
  }
  static func estimatedTips(_ route: Route) -> Int64 { 0 }
}
