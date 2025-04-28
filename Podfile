# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

target 'LMStoreKit' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  pod 'SwiftyStoreKit', '0.16.1'

  post_install do |installer|
    # 从项目中自动获取部署目标版本（推荐）
    project_target = '13.0' # 或从 Xcode 项目设置中动态获取
    
    installer.pods_project.targets.each do |target|
      # 方法一：统一设置所有第三方库
      target.build_configurations.each do |config|
        current_target = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
        
        # 如果当前目标 < 项目要求，则强制更新
        if current_target.to_f < project_target.to_f
          config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = project_target
        end
      end

    end
  end

  target 'LMStoreKitTests' do
    # Pods for testing
  end

end
