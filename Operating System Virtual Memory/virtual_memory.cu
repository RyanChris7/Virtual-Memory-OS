#include "virtual_memory.h"
#include <cuda.h>
#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>

__device__ void init_invert_page_table(VirtualMemory *vm)
{

  for (int i = 0; i < vm->PAGE_ENTRIES; i++)
  {
    vm->invert_page_table[i] = 0x80000000;                 // invalid := MSB is 1
    vm->invert_page_table[i + vm->PAGE_ENTRIES] = i;       // Page number
    vm->invert_page_table[i + (2 * vm->PAGE_ENTRIES)] = 0; // Count variable which stores the access time which is used in the recently_used
  }
}

__device__ void vm_init(VirtualMemory *vm, uchar *buffer, uchar *storage,
                        u32 *invert_page_table, int *pagefault_num_ptr,
                        int PAGESIZE, int INVERT_PAGE_TABLE_SIZE,
                        int PHYSICAL_MEM_SIZE, int STORAGE_SIZE,
                        int PAGE_ENTRIES)
{
  // init variables
  vm->buffer = buffer;
  vm->storage = storage;
  vm->invert_page_table = invert_page_table;
  vm->pagefault_num_ptr = pagefault_num_ptr;

  // init constants
  vm->PAGESIZE = PAGESIZE;
  vm->INVERT_PAGE_TABLE_SIZE = INVERT_PAGE_TABLE_SIZE;
  vm->PHYSICAL_MEM_SIZE = PHYSICAL_MEM_SIZE;
  vm->STORAGE_SIZE = STORAGE_SIZE;
  vm->PAGE_ENTRIES = PAGE_ENTRIES;

  // before first vm_write or vm_read
  init_invert_page_table(vm);
}

//Function Prototypes
__device__ int recently_used(VirtualMemory *vm, bool page_check, int index);
__device__ int page_search(VirtualMemory *vm, u32 page_number);
__device__ int update(VirtualMemory *vm, bool check, int index, u32 page_number);

// ===== Code Begin ===== //

__device__ int recently_used(VirtualMemory *vm, bool page_check, int index){
    if (page_check)
        return index;
    u32 used = vm->invert_page_table[2 * vm->PAGE_ENTRIES];
    int final_index = 0;
    int i = 1;

    while (i < vm->PAGE_ENTRIES){
        if (used < vm->invert_page_table[i + (2 * vm->PAGE_ENTRIES)])
        {
        used = vm->invert_page_table[i + (2 * vm->PAGE_ENTRIES)];
        final_index = i;
        }
        i++;
    }
    return final_index;
}

__device__ int page_search(VirtualMemory *vm, u32 page_number){ // Function to search and update page
    int i = 0;
    int index = -1;
    bool check = false;

    while(i < vm->PAGE_ENTRIES){  // Page search in main memory
        if (vm->invert_page_table[i + vm->PAGE_ENTRIES] == page_number){
            check = true;
            index = i;
            break;
        }
        i++;
    }

    // Update page
    index = update(vm, check, index, page_number);
    return index;
}

__device__ int update(VirtualMemory *vm, bool check, int index, u32 page_number){
    if (check)
    {
        if (vm->invert_page_table[index] != 0x80000000)
        return index;

        *(vm->pagefault_num_ptr) += 1;
        for (int i = 0; i < vm->PAGESIZE; i++)
            vm->buffer[(index * vm->PAGESIZE) + i] = vm->storage[(page_number * vm->PAGESIZE) + i];
        vm->invert_page_table[index] = 0x00000000;
        return index;
    }
    else {
        bool page_check = false;

        *(vm->pagefault_num_ptr) += 1; // Increase the pagefault number
        for (int i = 0; i < vm->PAGE_ENTRIES; i++)
        {
            if (vm->invert_page_table[i] == 0x80000000)
            {
            page_check = true;
            index = i;
            break;
            }
        }
        index = recently_used(vm, page_check, index);
    }

    // Write data from main memory to disk
    for (int i = 0; i < vm->PAGESIZE; i++)
        vm->storage[vm->invert_page_table[index + vm->PAGE_ENTRIES] * vm->PAGESIZE + i] =
            vm->buffer[index * vm->PAGESIZE + i];

    // Load data from disk to main memory
    for (int i = 0; i < vm->PAGESIZE; i++)
        vm->buffer[(index * vm->PAGESIZE) + i] = vm->storage[(page_number * vm->PAGESIZE) + i];
    vm->invert_page_table[index] = 0x00000000;

    // Update the invert page table
    vm->invert_page_table[index + vm->PAGE_ENTRIES] = page_number;
    return index;
}

__device__ uchar vm_read(VirtualMemory *vm, u32 addr){
    /* Complate vm_read function to read single element from data buffer */
    u32 page_number = addr / vm->PAGESIZE;
    u32 page_offset = addr % vm->PAGESIZE;

    int index = page_search(vm, page_number);
    uchar data = vm->buffer[(index * vm->PAGESIZE) + page_offset]; // Get data from main memory

    for (int i = 0; i < vm->PAGE_ENTRIES; i++)
        vm->invert_page_table[i + (2 * vm->PAGE_ENTRIES)] += 1;
    vm->invert_page_table[index + (2 * vm->PAGE_ENTRIES)] = 0; // Set the accessed page's count ot 0

    return data;
}


__device__ void vm_write(VirtualMemory *vm, u32 addr, uchar value){
    /* Complete vm_write function to write value into data buffer */
    u32 page_number = addr / vm->PAGESIZE;
    u32 page_offset = addr % vm->PAGESIZE;

    int index = page_search(vm, page_number);
    vm->buffer[(index * vm->PAGESIZE) + page_offset] = value; // write data to main memory

    for (int i = 0; i < vm->PAGE_ENTRIES; i++)
        vm->invert_page_table[i + (2 * vm->PAGE_ENTRIES)] += 1;
    vm->invert_page_table[index + (2 * vm->PAGE_ENTRIES)] = 0; // Set the accessed page's count ot 0
}


__device__ void vm_snapshot(VirtualMemory *vm, uchar *results, int offset,
                            int input_size){
    /* Complete snapshot function togther with vm_read to load elements from data to result buffer */
    for (int i = 0; i < input_size; i++)
        results[i + offset] = vm_read(vm, i);
}