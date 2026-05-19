OUTPUT_FORMAT("elf32-littlearm")
OUTPUT_ARCH(arm)

SECTIONS {
    /* Base Addr RCC: 0x40023800 - RCC_AHBIENR Offset: 0x30 */
    RCC_AHB1ENR = 0x40023830;

    /* Peripheral Enable */
    RCC_APB1ENR = 0x40023840;

    TIM2_CR1  = 0x40000000;
    TIM2_DIER = 0x4000000C;
    TIM2_SR   = 0x40000010;
    TIM2_EGR = 0x40000014;
    TIM2_PSC = 0x40000028;
    TIM2_ARR = 0x4000002C;

    NVIC_ISER0 = 0xE000E100;

    /* GPIOA Base Addr: 0x40020000 */

    /* MODER Offset: 0x0 */
    GPIOA_MODER = 0x40020000;
    /* Bit Set Reset Register Offset: 0x18 */
    GPIOA_BSRR =  0x40020018;
    /* Input Data Register Offset: 0x10 */
    GPIOA_IDR =  0x40020010;

    /* GPIOB Base Addr: 0x40020400 /*

    /* MODER Offset: 0x0 */
    GPIOB_MODER = 0x40020400;
    /* Bit Set Reset Register Offset: 0x18 */
    GPIOB_BSRR =  0x40020418;
    /* Input Data Register Offset: 0x10 */
    GPIOB_IDR =  0x40020410;

    /* GPIOC Base Addr: 0x40020800 */

    /* MODER Offset: 0x0 */
    GPIOC_MODER = 0x40020800;
    /* Bit Set Reset Register Offset: 0x18 */
    GPIOC_BSRR =  0x40020818;
    /* Input Data Register Offset: 0x10 */
    GPIOC_IDR =  0x40020810;

    . = 0x08000000;

    .vectors :
    {
        LONG(0x20001000)
        LONG(run + 1)

        . = 0xB0;
        LONG(tim2_handler + 1)
    }

    .rodata :
    {
        . = ALIGN(4);
        *(.rodata*)
    }

    .text :
    {
        . = ALIGN(4);
        *(.text*)
    }
}
