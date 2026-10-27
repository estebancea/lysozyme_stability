# System example

Example system: Bet:Sor:Tau:GPC:U (1:3.1:0.1:2.8:7.1) at 20 wt%, corresponding to system 18 in the manuscript (Bet = betaine, Sor = sorbitol, Tau = taurine, GPC = glycerophosphocholine, U = urea).

```text
#############################################
 ID: 18 | Bet:Sor:Tau:GPC:U (1:3.1:0.1:2.8:7.1) - 20 wt%
 T [K]:                               298.15
 P [bar]:                               1.01
#############################################
 * Number of molecules
   - lysozyme (PROA):                      1
   - betaine (BET):                       40
   - sorbitol (SOR):                     124
   - taurine (TAU):                        4
   - glycerophosphocholine (GPC):        112
   - urea (URE):                         284
   - water (SOL):                      16000
   - chloride ion (CLA):                   8
   - Total (excluding lysozyme):       16572
 * Initial box dimensions
   - Lx [nm]:                        8.43147
   - Ly [nm]:                        8.43147
   - Lz [nm]:                        8.43147
#############################################
```

## Files

* `system.inp`: Packmol input used to build the initial configuration
* `system.top`: GROMACS topology (includes the parameters in `../ff/`)
* `run_example.sh`: complete workflow (Packmol, energy minimization, equilibration, production and analysis)

## Running the example

```bash
bash run_example.sh
```

The script can be launched from any directory. Simulation files are written to `MD/system_18/run_1/` and analysis results (`.xvg`) to `results/system_18/run_1/`, both in the repository root.