import SwiftUI
import SwiftData
import Charts

struct MainShell: View {
 var body: some View { TabView {
   NavigationStack { HomeView() }.tabItem { Label("Главная",systemImage:"house.fill") }
   NavigationStack { CalendarViewKX() }.tabItem { Label("Календарь",systemImage:"calendar") }
   NavigationStack { CustomersView() }.tabItem { Label("Клиенты",systemImage:"person.2.fill") }
   NavigationStack { SalaryView() }.tabItem { Label("Зарплата",systemImage:"chart.bar.fill") }
   NavigationStack { MoreView() }.tabItem { Label("Ещё",systemImage:"square.grid.2x2.fill") }
 } }
}

struct HomeView: View {
 @Query(sort:\Shift.date, order:.reverse) var shifts:[Shift]
 @Query var routes:[Route]
 var orders:Int { routes.filter{$0.deletedAt == nil}.reduce(0){$0+$1.factualOrders} }
 var tips:Double { Double(routes.filter{$0.deletedAt == nil}.reduce(Int64(0)){$0+$1.tipsHellers})/100 }
 var body: some View { ScrollView { VStack(spacing:14) {
   HStack { VStack(alignment:.leading){ Text("KurierX").font(.largeTitle.bold()); Text("Курьерская аналитика").foregroundStyle(.secondary) }; Spacer() }
   GoalCard(current:orders,target:1000)
   HStack { Metric(title:"Заказы",value:"\(orders)",icon:"shippingbox.fill"); Metric(title:"Чаевые",value:String(format:"%.2f Kč",tips),icon:"banknote.fill") }
   Metric(title:"Смены",value:"\(shifts.count)",icon:"clock.fill")
 }.padding() }.navigationBarHidden(true) }
}
struct GoalCard: View { let current:Int,target:Int; var body:some View { VStack(alignment:.leading,spacing:7){ HStack{Text("Цель").bold();Spacer();Text("\(current) / \(target)")}; ProgressView(value:Double(current),total:Double(max(target,1))); Text("Осталось \(max(0,target-current)) заказов").font(.caption).foregroundStyle(.secondary) }.padding().background(.thinMaterial,in:RoundedRectangle(cornerRadius:18)) } }
struct Metric: View { let title,value,icon:String; var body:some View { HStack{Image(systemName:icon).font(.title2);VStack(alignment:.leading){Text(title).font(.caption).foregroundStyle(.secondary);Text(value).font(.title3.bold())};Spacer()}.padding().frame(maxWidth:.infinity).background(.thinMaterial,in:RoundedRectangle(cornerRadius:18)) } }

struct CalendarViewKX: View { @Query(sort:\Shift.date) var shifts:[Shift]; var body:some View { List(shifts){ s in HStack{Text(s.date,style:.date);Spacer();Text(s.warehouseRaw)} }.navigationTitle("Календарь") } }
struct CustomersView: View { @Query var customers:[Customer]; var body:some View { List(customers.filter{$0.deletedAt==nil}){ c in VStack(alignment:.leading){Text("\(c.firstName) \(c.lastName)").bold();Text(c.address).font(.caption).foregroundStyle(.secondary);Text("Пакеты: \(c.bags) · Чаевые: \(Double(c.tipsHellers)/100, specifier:"%.2f") Kč").font(.caption)} }.navigationTitle("Клиенты") } }

struct SalaryView: View { @Query var routes:[Route]; var body:some View { ScrollView { Chart(routes.filter{$0.deletedAt==nil}) { r in BarMark(x:.value("Круг",r.sequence),y:.value("Заказы",r.factualOrders)) }.frame(height:240).padding(); Text("Детальная помесячная аналитика использует локальные данные KurierX.").foregroundStyle(.secondary).padding() }.navigationTitle("Зарплата") } }

struct MoreView: View { var body:some View { List { NavigationLink("Смены",destination:Placeholder(title:"Смены")); NavigationLink("Бонусы и штрафы",destination:Placeholder(title:"Бонусы и штрафы")); NavigationLink("Статистика",destination:Placeholder(title:"Статистика")); NavigationLink("Резервные копии",destination:Placeholder(title:"Резервные копии")); NavigationLink("Журнал",destination:Placeholder(title:"Журнал")); NavigationLink("Корзина",destination:Placeholder(title:"Корзина")); NavigationLink("Настройки",destination:Placeholder(title:"Настройки")) }.navigationTitle("Ещё") } }
struct Placeholder:View { let title:String; var body:some View { ContentUnavailableView(title,systemImage:"hammer.fill",description:Text("Экран подключён к iOS-проекту и готов для переноса Android-логики.")) } }
