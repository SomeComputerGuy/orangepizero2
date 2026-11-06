/* vkprops: print what the first Vulkan device reports for the 1.1 checks (apiVersion, subgroup and 1.1 core
 * properties/features, ARM core-builtin properties) and create a device with every 1.1 core feature it reports.
 * Exit 0 only if apiVersion >= 1.1 and vkCreateDevice succeeds. Host (drm-shim) and board (arm64). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("FAIL %s -> %d\n", #x, r_); return 1; } } while (0)
int main(void)
{
   VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO, .apiVersion = VK_API_VERSION_1_1 };
   VkInstanceCreateInfo ici = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &app };
   VkInstance inst; CK(vkCreateInstance(&ici, NULL, &inst));
   uint32_t n = 1; VkPhysicalDevice pd; VkResult r = vkEnumeratePhysicalDevices(inst, &n, &pd);
   if ((r != VK_SUCCESS && r != VK_INCOMPLETE) || n == 0) { printf("FAIL no physical device (%d)\n", r); return 1; }
   VkPhysicalDeviceShaderCoreBuiltinsPropertiesARM cb = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SHADER_CORE_BUILTINS_PROPERTIES_ARM };
   VkPhysicalDeviceVulkan11Properties p11 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_PROPERTIES, .pNext = &cb };
   VkPhysicalDeviceProperties2 p = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, .pNext = &p11 };
   vkGetPhysicalDeviceProperties2(pd, &p);
   uint32_t v = p.properties.apiVersion;
   printf("deviceName %s\napiVersion %u.%u.%u\n", p.properties.deviceName, VK_API_VERSION_MAJOR(v), VK_API_VERSION_MINOR(v), VK_API_VERSION_PATCH(v));
   printf("subgroupSize %u\nsubgroupSupportedStages 0x%x\nsubgroupSupportedOperations 0x%x\nsubgroupQuadOperationsInAllStages %u\n",
          p11.subgroupSize, p11.subgroupSupportedStages, p11.subgroupSupportedOperations, p11.subgroupQuadOperationsInAllStages);
   printf("maxMultiviewViewCount %u\nmaxMultiviewInstanceIndex %u\nprotectedNoFault %u\nmaxPerSetDescriptors %u\nmaxMemoryAllocationSize %llu\n",
          p11.maxMultiviewViewCount, p11.maxMultiviewInstanceIndex, p11.protectedNoFault, p11.maxPerSetDescriptors,
          (unsigned long long)p11.maxMemoryAllocationSize);
   printf("shaderCoreMask 0x%llx\nshaderCoreCount %u\nshaderWarpsPerCore %u\n", (unsigned long long)cb.shaderCoreMask, cb.shaderCoreCount, cb.shaderWarpsPerCore);
   VkPhysicalDeviceVulkan11Features f11 = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES };
   VkPhysicalDeviceFeatures2 f = { .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &f11 };
   vkGetPhysicalDeviceFeatures2(pd, &f);
   printf("f11 storageBuffer16BitAccess %u uniformAndStorageBuffer16BitAccess %u storagePushConstant16 %u storageInputOutput16 %u\n",
          f11.storageBuffer16BitAccess, f11.uniformAndStorageBuffer16BitAccess, f11.storagePushConstant16, f11.storageInputOutput16);
   printf("f11 multiview %u multiviewGeometryShader %u multiviewTessellationShader %u variablePointersStorageBuffer %u variablePointers %u\n",
          f11.multiview, f11.multiviewGeometryShader, f11.multiviewTessellationShader, f11.variablePointersStorageBuffer, f11.variablePointers);
   printf("f11 protectedMemory %u samplerYcbcrConversion %u shaderDrawParameters %u\n",
          f11.protectedMemory, f11.samplerYcbcrConversion, f11.shaderDrawParameters);
   uint32_t ne = 0; vkEnumerateDeviceExtensionProperties(pd, NULL, &ne, NULL);
   VkExtensionProperties *e = calloc(ne, sizeof(*e)); vkEnumerateDeviceExtensionProperties(pd, NULL, &ne, e);
   printf("deviceExtensions %u\n", ne);
   for (uint32_t i = 0; i < ne; i++) printf("ext %s\n", e[i].extensionName);
   float prio = 1.0f;
   VkDeviceQueueCreateInfo q = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueCount = 1, .pQueuePriorities = &prio };
   VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, .pNext = &f, .queueCreateInfoCount = 1, .pQueueCreateInfos = &q };
   VkDevice dev; CK(vkCreateDevice(pd, &dci, NULL, &dev));
   printf("createDevice OK (all reported 1.0 + 1.1 core features enabled)\n");
   vkDestroyDevice(dev, NULL); vkDestroyInstance(inst, NULL);
   if (VK_API_VERSION_MINOR(v) < 1) { printf("FAIL apiVersion < 1.1\n"); return 1; }
   printf("VKPROPS-OK\n");
   return 0;
}
