/* Minimal Vulkan compute runner: vkcomp <file.spv> <lx> <ly> <lz> <gx> <gy> <gz> <nbufs> [bufbytes]
 * Creates a compute pipeline from the SPIR-V (spec constants 0,1,2 = local size, like dEQP's subgroup tests),
 * binds nbufs zeroed host-visible storage buffers at set 0 bindings 0..n-1, dispatches gx*gy*gz groups, waits
 * on a fence (10 s) and prints the first 32 uints of buffer 0. Meant for the fork panvk under the drm-shim. */
#include <vulkan/vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define CK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { fprintf(stderr, "%s -> %d\n", #x, r_); exit(1); } } while (0)
int main(int argc, char **argv) {
   if (argc < 9) { fprintf(stderr, "usage: see source\n"); return 2; }
   FILE *f = fopen(argv[1], "rb"); if (!f) { perror(argv[1]); return 1; }
   fseek(f, 0, SEEK_END); long sz = ftell(f); fseek(f, 0, SEEK_SET);
   uint32_t *code = malloc(sz); fread(code, 1, sz, f); fclose(f);
   uint32_t ls[3] = { atoi(argv[2]), atoi(argv[3]), atoi(argv[4]) };
   uint32_t gs[3] = { atoi(argv[5]), atoi(argv[6]), atoi(argv[7]) };
   unsigned nbufs = atoi(argv[8]); size_t bufsz = argc > 9 ? atol(argv[9]) : 1 << 20;
   VkApplicationInfo ai = { VK_STRUCTURE_TYPE_APPLICATION_INFO, .pApplicationName = "vkcomp", .apiVersion = VK_API_VERSION_1_3 };
   VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, .pApplicationInfo = &ai };
   VkInstance inst; CK(vkCreateInstance(&ici, NULL, &inst));
   uint32_t n = 1; VkPhysicalDevice pd; CK(vkEnumeratePhysicalDevices(inst, &n, &pd));
   VkPhysicalDeviceProperties pp; vkGetPhysicalDeviceProperties(pd, &pp);
   VkPhysicalDeviceSubgroupProperties sgp = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SUBGROUP_PROPERTIES };
   VkPhysicalDeviceProperties2 pp2 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2, &sgp };
   vkGetPhysicalDeviceProperties2(pd, &pp2);
   fprintf(stderr, "device %s api %u.%u.%u subgroupSize %u\n", pp.deviceName, VK_VERSION_MAJOR(pp.apiVersion),
           VK_VERSION_MINOR(pp.apiVersion), VK_VERSION_PATCH(pp.apiVersion), sgp.subgroupSize);
   uint32_t qc = 0; vkGetPhysicalDeviceQueueFamilyProperties(pd, &qc, NULL);
   VkQueueFamilyProperties *qf = calloc(qc, sizeof *qf); vkGetPhysicalDeviceQueueFamilyProperties(pd, &qc, qf);
   uint32_t qi = 0; for (; qi < qc; qi++) if (qf[qi].queueFlags & VK_QUEUE_COMPUTE_BIT) break;
   float prio = 1.0f;
   VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, .queueFamilyIndex = qi, .queueCount = 1, .pQueuePriorities = &prio };
   /* enable every feature the device has (dEQP enables what each test needs; we take all) */
   VkPhysicalDeviceVulkan12Features f12 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_2_FEATURES };
   VkPhysicalDeviceVulkan11Features f11 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_1_FEATURES, &f12 };
   VkPhysicalDeviceFeatures2 f2 = { VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, &f11 };
   vkGetPhysicalDeviceFeatures2(pd, &f2);
   VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, getenv("VKCOMP_ALLFEAT") ? (void *)&f2 : NULL, .queueCreateInfoCount = 1, .pQueueCreateInfos = &qci };
   VkDevice dev; CK(vkCreateDevice(pd, &dci, NULL, &dev));
   VkQueue q; vkGetDeviceQueue(dev, qi, 0, &q);
   VkShaderModuleCreateInfo smci = { VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO, .codeSize = sz, .pCode = code };
   VkShaderModule sm; CK(vkCreateShaderModule(dev, &smci, NULL, &sm));
   VkDescriptorSetLayoutBinding *b = calloc(nbufs, sizeof *b);
   for (unsigned i = 0; i < nbufs; i++) b[i] = (VkDescriptorSetLayoutBinding){ i, VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, 1, VK_SHADER_STAGE_COMPUTE_BIT };
   VkDescriptorSetLayoutCreateInfo dslci = { VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO, .bindingCount = nbufs, .pBindings = b };
   VkDescriptorSetLayout dsl; CK(vkCreateDescriptorSetLayout(dev, &dslci, NULL, &dsl));
   VkPipelineLayoutCreateInfo plci = { VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO, .setLayoutCount = 1, .pSetLayouts = &dsl };
   VkPipelineLayout pl; CK(vkCreatePipelineLayout(dev, &plci, NULL, &pl));
   VkSpecializationMapEntry me[3] = { {0, 0, 4}, {1, 4, 4}, {2, 8, 4} };
   VkSpecializationInfo si = { 3, me, sizeof ls, ls };
   VkComputePipelineCreateInfo cpci = { VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
      .stage = { VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO, .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = sm, .pName = "main", .pSpecializationInfo = &si },
      .layout = pl };
   VkPipeline pipe; CK(vkCreateComputePipelines(dev, VK_NULL_HANDLE, 1, &cpci, NULL, &pipe));
   fprintf(stderr, "pipeline created (local %u %u %u)\n", ls[0], ls[1], ls[2]);
   VkPhysicalDeviceMemoryProperties mp; vkGetPhysicalDeviceMemoryProperties(pd, &mp);
   uint32_t mt = 0; for (; mt < mp.memoryTypeCount; mt++) if (mp.memoryTypes[mt].propertyFlags & VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT) break;
   VkBuffer *bufs = calloc(nbufs, sizeof *bufs); void **maps = calloc(nbufs, sizeof *maps);
   VkDescriptorBufferInfo *dbi = calloc(nbufs, sizeof *dbi); VkWriteDescriptorSet *wds = calloc(nbufs, sizeof *wds);
   VkDescriptorPoolSize ps = { VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, nbufs ? nbufs : 1 };
   VkDescriptorPoolCreateInfo dpci = { VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO, .maxSets = 1, .poolSizeCount = 1, .pPoolSizes = &ps };
   VkDescriptorPool dp; CK(vkCreateDescriptorPool(dev, &dpci, NULL, &dp));
   VkDescriptorSetAllocateInfo dsai = { VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO, .descriptorPool = dp, .descriptorSetCount = 1, .pSetLayouts = &dsl };
   VkDescriptorSet ds; CK(vkAllocateDescriptorSets(dev, &dsai, &ds));
   for (unsigned i = 0; i < nbufs; i++) {
      VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, .size = bufsz, .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT };
      CK(vkCreateBuffer(dev, &bci, NULL, &bufs[i]));
      VkMemoryRequirements mr; vkGetBufferMemoryRequirements(dev, bufs[i], &mr);
      VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, .allocationSize = mr.size, .memoryTypeIndex = mt };
      VkDeviceMemory mem; CK(vkAllocateMemory(dev, &mai, NULL, &mem)); CK(vkBindBufferMemory(dev, bufs[i], mem, 0));
      CK(vkMapMemory(dev, mem, 0, bufsz, 0, &maps[i])); memset(maps[i], 0, bufsz);
      dbi[i] = (VkDescriptorBufferInfo){ bufs[i], 0, VK_WHOLE_SIZE };
      wds[i] = (VkWriteDescriptorSet){ VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET, .dstSet = ds, .dstBinding = i, .descriptorCount = 1,
                                       .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &dbi[i] };
   }
   if (nbufs) vkUpdateDescriptorSets(dev, nbufs, wds, 0, NULL);
   VkCommandPoolCreateInfo cpi = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, .queueFamilyIndex = qi };
   VkCommandPool cp; CK(vkCreateCommandPool(dev, &cpi, NULL, &cp));
   VkCommandBufferAllocateInfo cbai = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, .commandPool = cp, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1 };
   VkCommandBuffer cb; CK(vkAllocateCommandBuffers(dev, &cbai, &cb));
   VkCommandBufferBeginInfo cbbi = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
   CK(vkBeginCommandBuffer(cb, &cbbi));
   vkCmdBindPipeline(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pipe);
   vkCmdBindDescriptorSets(cb, VK_PIPELINE_BIND_POINT_COMPUTE, pl, 0, 1, &ds, 0, NULL);
   vkCmdDispatch(cb, gs[0], gs[1], gs[2]);
   CK(vkEndCommandBuffer(cb));
   VkFenceCreateInfo fci = { VK_STRUCTURE_TYPE_FENCE_CREATE_INFO }; VkFence fence; CK(vkCreateFence(dev, &fci, NULL, &fence));
   VkSubmitInfo sub = { VK_STRUCTURE_TYPE_SUBMIT_INFO, .commandBufferCount = 1, .pCommandBuffers = &cb };
   CK(vkQueueSubmit(q, 1, &sub, fence));
   VkResult wr = vkWaitForFences(dev, 1, &fence, VK_TRUE, 10000000000ull);
   fprintf(stderr, "dispatch %u %u %u: wait -> %d\n", gs[0], gs[1], gs[2], wr);
   if (nbufs) { uint32_t *u = maps[0]; for (int i = 0; i < 32; i++) printf("%u%c", u[i], i % 16 == 15 ? '\n' : ' '); }
   return wr == VK_SUCCESS ? 0 : 3;
}
