//
//  ViewController.swift
//  OilTester
//
//  Created by Derrick on 2024/3/15.
//

import UIKit
import SPIndicator
import SwifterSwift
import SVProgressHUD
class PeripheralInfo {
    var peripheral:CBPeripheral?
    var isConnected = false
}

class ViewController: UIViewController,UITableViewDataSource,UITableViewDelegate {
    
    let baby = BabyBluetooth.share()
    var datas:[PeripheralInfo] = []
    var curPeripheral:CBPeripheral?
    var writeCharacteristic: CBCharacteristic?
    var readCharacteristic: CBCharacteristic?
    var infoTableView:UITableView!
    var historyTableView:UITableView!
    let tpmLabel = UILabel()
    let tempLabel = UILabel()
    let timeLabel = UILabel()
    var deviceID = ""
    var historys:[TemperatureHistoryData] = []
    var lastesOffsetY:CGFloat = 0
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.title = "Oil-Tester"
        
        addTempLabel()
        addTableView()
        addHistoryTableView()
        addSendButton()
        
        
        
        baby?.cancelAllPeripheralsConnection()
        
        sleep(1)
        
        // 开始搜索
        baby?.scanForPeripherals().begin()
        
        baby?.setBlockOnCentralManagerDidUpdateState({ [weak self] manager in
         
            switch manager?.state {
            case .poweredOn:
                self?.connect()
            case .poweredOff:
                SPIndicator.present(title: "Bluetooth PoweredOff", haptic: .warning)
            case .unauthorized:
                let alert = UIAlertController(title: "Bluetooth Unauthorized", message: "Please enable Bluetooth permission in settings", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
                alert.addAction(UIAlertAction(title: "Confirm", style: .default,handler: { _ in
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        if UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        }
                    }
                }))
                self?.present(alert, animated: true)
                SPIndicator.present(title: "Bluetooth Unauthorized", haptic: .warning)
            default:
                print(manager?.state.rawValue.description ?? "")
            }
        })
        
        // 连接oil开头的设备
        baby?.setFilterOnDiscoverPeripherals({ (name, adv, rssi)  -> Bool in
            guard let name = name else { return false }
            print("name:\(name),adv:\(adv),rssi:\(rssi)")
            
            //                        if name.lowercased().contains("Oil") {
            //                            return true
            //                        }
            if name.count > 1 { return true}
            return false
        })
        
        // 找到Peripherals的委托
        baby?.setBlockOnDiscoverToPeripherals({ [weak self]  center, peripher, advertisementData, RSSI in
            guard let `self` = self else { return }
            guard let peripher = peripher,let adv = advertisementData else { return }
            print("搜索到设备:\(peripher.name ?? "")")
            let data = PeripheralInfo()
            data.peripheral = peripher
            
            if self.datas.contains(where: { $0.peripheral?.name == peripher.name }) {
                return
            }
            self.datas.append(data)
            self.infoTableView.reloadData()
        })
        
        // 连接成功
        baby?.setBlockOnConnected({ [weak self] manager, peripher in
            print("连接成功")
            SVProgressHUD.dismiss()
            guard let `self` = self else { return }
            if peripher  == self.curPeripheral {
                
                UIView.animate(withDuration: 0.2) {
                    self.infoTableView.alpha = 0
                }
                
                SPIndicator.present(title: "Connected", preset: .done)
            }
            
        })
        
        // 连接失败
        baby?.setBlockOnFailToConnect({ manager, peripher,error in
            if error != nil {
                print("setBlockOnFailToConnect:\(error.debugDescription)")
                if peripher == self.curPeripheral {
                    SPIndicator.present(title: "Connect Failed", haptic: .error)
                }
                
            }
        })
        
        // 连接断开
        baby?.setBlockOnDisconnect({ manager, peripheral, error in
            print("setBlockOnDisconnect:\(error.debugDescription)")
            if  peripheral == self.curPeripheral {
                SPIndicator.present(title: "Device Disconnect", haptic: .error)
            }
            
        })
        
        //设置发现设备的Services的委托/
        //        baby?.setBlockOnDiscoverServices({ peripheral, error in
        //            if error == nil {
        //                peripheral?.services?.forEach({
        //                    print("peripheral?.services:\($0.description)")
        //                })
        //            } else {
        //                print(error.debugDescription)
        //            }
        //        })
        //
        //设置发现设service的Characteristics的委托
        baby?.setBlockOnDiscoverCharacteristics({ peripheral, service, error in
            print("service name:\(service?.uuid)")
            guard let service = service else { return }
            service.characteristics?.forEach({ t in
                print(t.uuid)
                if t.uuid == CBUUID.init(string: "FE62") {// 通知属性
                    self.readCharacteristic = t
                    self.curPeripheral?.setNotifyValue(true, for: self.readCharacteristic!)
                }
                if t.uuid == CBUUID.init(string: "FE61") {// 写属性
                    self.writeCharacteristic = t
                }
            })
            
            
        })
        
        //设置读取characteristics的委托
        baby?.setBlockOnReadValueForCharacteristic({ [weak self] peripheral, characteristic, error in
            guard let `self` = self else { return }
            
            guard let value = characteristic?.value,let data = String.init(data: value, encoding: .utf8) else { return }
            
            
            
            // 命令标识 2-4 01 信息上报
            let commandTag = data.slicing(from: 2, length: 2)
            // 应答标志 00 空闲 命令帧或上传数据帧时，应答标识符默认 00
            let resTag = data.slicing(from: 4, length: 2)
            // 设备id 8 位门店编号+ 2 位仪器编号
            let deviceId = data.slicing(from: 6, length: 10) ?? ""
            self.deviceID = deviceId
            // 数据帧的发送时间
            let dataSedTime = data.slicing(from: 16, length: 12)
            // 数据长度
            let dataLength = data.slicing(from: 30, length: 5)?.replacingOccurrences(of: "0", with: "").int ?? 0
            let dataContent = data.slicing(from: 35, length: dataLength)
            
            
            // 0001 实时测量数据 0002 历史数据
            let dataTypeTag = dataContent?.slicing(from: 0, length: 4)
            let dataRecTime = dataContent?.slicing(from: 4, length: 12) ?? ""
            let dataContentLength = dataContent?.slicing(from: 16, length: 5)?.replacingOccurrences(of: "0", with: "").int ?? 0
            let dataContentStr = dataContent?.slicing(from: 21, length: dataContentLength)
            
            // 200104173550
            let yy = dataRecTime.slicing(from: 0, length: 2)  ?? ""
            let MM = dataRecTime.slicing(from: 2, length: 2)  ?? ""
            let dd = dataRecTime.slicing(from: 4, length: 2)  ?? ""
            let HH = dataRecTime.slicing(from: 6, length: 2)  ?? ""
            let mm = dataRecTime.slicing(from: 8, length: 2)  ?? ""
            let ss = dataRecTime.slicing(from: 10, length: 2)  ?? ""
            let updateTime = "\(yy)/\(MM)/\(dd) \(HH):\(mm):\(ss)"
            if dataContentStr == nil { return }
            
            if commandTag == "01" { // 信息上报
                //                print("信息上报 data:\(String(describing: dataContentStr))")
                // ##0100000000010120010416505001000330001200104165050000121019.7C05.5%##
                //  1019.7C05.5%
                let temp = dataContentStr?.slicing(from: 2, length: 4)
                let tempUnit = dataContentStr?.slicing(from: 6, length: 1)
                if tempUnit == "C" {
                    tempLabel.text = "\(temp ?? "")℃"
                } else {
                    tempLabel.text = "\(temp ?? "")℉"
                }
                let tpm = dataContentStr?.slicing(from: 7, length: 5)?.removingPrefix("0") ?? ""
                tpmLabel.text = "TPM:\(tpm)"
                
                
                timeLabel.text = "update at:\(updateTime)"
            }
            
            if commandTag == "80" { // 查询命令
                //  ## 80 01 0000000101 200101202450 01 00038 0003 200101150011 00016 00002 021.0C05.5%##
                // 00002021.0C05.5%
                print("查询命令 data:\(String(describing: dataContentStr))")
                var temp = dataContentStr?.slicing(from: 6, length: 4) ?? ""
                let tempUnit = dataContentStr?.slicing(from: 10, length: 1)
                if tempUnit == "C" {
                    temp.append("℃")
                } else {
                    temp.append("℉")
                }
                let tpm = dataContentStr?.slicing(from: 11, length: 5)?.removingPrefix("0") ?? ""
                let history = TemperatureHistoryData(tpm: tpm, temperature: temp, time: updateTime)
                historys.append(history)
                self.historyTableView.reloadData()
            }
            
            
        })
        
        
    }
    
    func addTableView() {
        infoTableView = UITableView(frame: self.view.bounds, style: .insetGrouped)
        view.addSubview(infoTableView)
        
        infoTableView.delegate = self
        infoTableView.dataSource = self
        infoTableView.rowHeight = 44
    }
    
    func addHistoryTableView() {
        historyTableView = UITableView(frame: CGRect(x: 0, y: kScreenHeight, width: kScreenWidth, height: kScreenHeight * 0.75), style: .insetGrouped)
        view.addSubview(historyTableView)
        
        historyTableView.delegate = self
        historyTableView.dataSource = self
        historyTableView.rowHeight = 80
        
        let closeButton = UIButton()
        historyTableView.addSubview(closeButton)
        closeButton.addTarget(self, action: #selector(closeHistory), for: .touchUpInside)
        closeButton.frame = CGRect(x: 0, y: 8, width: 50, height: 8)
        closeButton.center.x = self.view.center.x
        closeButton.layerCornerRadius = 4
        closeButton.backgroundColor = .systemBlue
    }
    
    @objc func closeHistory() {
        UIView.animate(withDuration: 0.5) {
            self.historyTableView.frame.origin.y = kScreenHeight
        }
    }
    
    func addSendButton() {
        let button = UIButton()
        button.setTitle("History", for: .normal)
        button.setTitleColor(.systemBlue, for: .normal)
        button.addTarget(self, action: #selector(sendAction), for: .touchUpInside)
        self.navigationItem.rightBarButtonItem = UIBarButtonItem(customView: button)
        
        
        let button1 = UIButton()
        button1.setTitle("Scan", for: .normal)
        button1.setTitleColor(.systemBlue, for: .normal)
        button1.addTarget(self, action: #selector(reScanAction), for: .touchUpInside)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: button1)
    }
    
    func addTempLabel() {
        
        view.addSubview(tpmLabel)
        tpmLabel.textColor = .black
        tpmLabel.font = UIFont.systemFont(ofSize: 40, weight: .bold)
        tpmLabel.textAlignment = .center
        tpmLabel.frame = CGRect(x: 0, y: self.view.center.y - 120, width: kScreenWidth, height: 40)
        
        view.addSubview(tempLabel)
        tempLabel.textColor = .black
        tempLabel.font = UIFont.systemFont(ofSize: 40, weight: .bold)
        tempLabel.textAlignment = .center
        tempLabel.frame = CGRect(x: 0, y: tpmLabel.frame.maxY + 40, width: kScreenWidth, height: 40)
        
        view.addSubview(timeLabel)
        timeLabel.textColor = .systemGray
        timeLabel.font = UIFont.systemFont(ofSize: 16, weight: .regular)
        timeLabel.textAlignment = .center
        timeLabel.frame = CGRect(x: 0, y: tempLabel.frame.maxY + 40, width: kScreenWidth, height: 40)
        
    }
    
    @objc func reScanAction() {
        
        UIView.animate(withDuration: 0.3) {
            self.historyTableView.frame.origin.y = kScreenHeight
        }
        UIView.animate(withDuration: 0.2) {
            self.infoTableView.alpha = 1
        }
        
        baby?.scanForPeripherals().begin()
    }
    
    
    @objc func sendAction() {
        
        guard let write = self.writeCharacteristic else {
            SPIndicator.present(title: "No Device Connected", haptic: .error)
            return
        }
        
        historys = []
        
        UIView.animate(withDuration: 0.3) {
            self.historyTableView.frame.origin.y = kScreenHeight * 0.25
        }
        
        let start = "##"
        // 命令单元  80 查询命令 数据帧为命令帧时，应答标识符默认 00
        let commandUnit = "8000"
        // 设备id 8 位门店编号+ 2 位仪器编号
        let deviceId = deviceID
        // 数据帧的发送时间
        let time = Date().string(withFormat: "yyMMddHHmmss")
        // 数据加密方式 默认不加密
        let encryType = "01"
        
        for i in 1..<10 {
            let dataUnit = dataUnit(i<10 ? "0\(i)" : i.string)
            // 有效值数据单元字总长度，长度范围：00000-65535，共 5 位字符
            let dataLength = "00033"
            let end = "##"
            
            let value = start + commandUnit + deviceId + time + encryType + dataLength + dataUnit + end
            
            let data = value.data(using: .utf8)
            
            self.curPeripheral?.writeValue(data!, for: write, type: .withResponse)
        }
        
    }
    
    
    func dataUnit(_ num:String) -> String {
        // 信息类型标志 0003 历史数据
        let dataType = "0003"
        // 实时查询时间 12 位
        let time = Date().string(withFormat: "yyMMddHHmmss")
        // 数据内容字符长度，默认 00012，即 12 位字符
        let contentLength = "00012"
        // 实时测量数据查询命令帧，数据内容默认为 0
        let content = "0000000000\(num)"
        return dataType + time + contentLength + content
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == infoTableView {
            return datas.count
        } else {
            return historys.count
        }
        
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        if tableView == infoTableView {
            if datas.count > 0 {
                cell.textLabel?.text = datas[indexPath.row].peripheral?.name
                cell.accessoryType = datas[indexPath.row].isConnected ? .checkmark : .none
            }
        } else {
            if historys.count > 0 {
                let data = historys[indexPath.row]
                let text = "TPM:\(data.tpm) \(data.temperature) \n \(data.time)"
                cell.textLabel?.numberOfLines = 2
                cell.textLabel?.text = text
            }
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        datas.forEach({
            $0.isConnected = false
        })
        
        SVProgressHUD.show(withStatus: "Connecting")
        
        let peripher = datas[indexPath.row].peripheral
        datas[indexPath.row].isConnected = true
        self.curPeripheral = peripher
        
        
        connect()
        
        
    }
    
    
    func connect() {
        //设置peripheral 然后读取services,然后读取characteristics名称和值和属性，获取characteristics对应的description的名称和值
        //self.peripheral是一个CBPeripheral实例
        guard let peripheral = self.curPeripheral else { return }
        self.baby?.having(peripheral)
            .connectToPeripherals()
            .discoverServices()
            .discoverCharacteristics()
            .readValueForCharacteristic()
            .discoverDescriptorsForCharacteristic()
            .readValueForDescriptors()
            .begin()
        self.baby?.autoReconnect(peripheral)
    }
    
}

extension UIApplication {
    // 查找keyWindow
    var keyWindow: UIWindow? {
        UIApplication
            .shared
            .connectedScenes
            .flatMap { ($0 as? UIWindowScene)?.windows ?? [] }
            .filter({ $0.isKeyWindow })
            .last
    }
}


extension UIDevice {
    static let window = UIApplication.shared.keyWindow
    
    static var topSafeAreaMargin:CGFloat {
        return UIApplication.shared.keyWindow?.safeAreaInsets.top ?? 0
    }
    static var bottomSafeAreaMargin:CGFloat {
        return UIApplication.shared.keyWindow?.safeAreaInsets.bottom ?? 0
    }
    static var navigationBarHeight:CGFloat {
        return 44.0
    }
    static var tabbarHeight:CGFloat {
        return 49.0
    }
    static var statusBarHeight:CGFloat {
        let statusBarManager = UIApplication
            .shared
            .connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.statusBarManager }
            .last
        return statusBarManager?.statusBarFrame.size.height ?? 0
    }
    
    static var isiPhoneX:Bool {
        topSafeAreaMargin > 0
    }
}


/// 导航栏总高度
var kNavBarHeight: CGFloat {
    return UIDevice.navigationBarHeight + UIDevice.statusBarHeight
}
/// tab栏高度总高度
var kTabBarHeight: CGFloat {
    return UIDevice.tabbarHeight + UIDevice.bottomSafeAreaMargin
}
/// 底部安全区域
let kBottomsafeAreaMargin: CGFloat = UIDevice.bottomSafeAreaMargin
/// 顶部安全区域
let kTopsafeAreaMargin: CGFloat = UIDevice.topSafeAreaMargin
/// 状态栏高度
let kStatusBarHeight: CGFloat = UIDevice.statusBarHeight
/// 屏幕高度
let kScreenHeight:CGFloat = UIScreen.main.bounds.size.height
/// 屏幕宽度
let kScreenWidth:CGFloat = UIScreen.main.bounds.size.width

