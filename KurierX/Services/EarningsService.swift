import Foundation

enum EarningsService {
    static func routeBaseHellers(type: RouteType, orders: Int) -> Int64 {
        // Mirrors Android-style local calculation structure. Values remain editable by the
        // route's explicit grossHellers field when imported OCR provides a factual result.
        let perOrder: Int64
        switch type { case .ot: perOrder = 4200; case .region: perOrder = 4700; case .express: perOrder = 5200 }
        return Int64(max(0, orders)) * perOrder
    }

    static func routeGross(_ route: Route) -> Int64 {
        route.grossHellers != 0 ? route.grossHellers : routeBaseHellers(type: route.type, orders: route.factualOrders)
    }
}
